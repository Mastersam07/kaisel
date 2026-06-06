import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

sealed class _R extends KaiselRoute {
  const _R();
}

final class _A extends _R {
  const _A();
}

final class _B extends _R {
  const _B();
}

final class _C extends _R {
  const _C(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

class _Parser extends RouteInformationParser<KaiselConfig<_R>> {
  _Parser(this.router);
  final KaiselRouter<_R> router;
  @override
  Future<KaiselConfig<_R>> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    return KaiselConfig<_R>(mainStack: router.stack);
  }
}

// A second branch route type, so the shell has two heterogeneous
// branches like a real bottom-nav app.
sealed class _Tab extends KaiselRoute {
  const _Tab();
}

final class _TabRoot extends _Tab {
  const _TabRoot();
}

/// A distinctive marker the branch's pageWrapper injects around the
/// page's child. Its presence in the tree proves the inner navigator
/// actually invoked the branch's wrapper rather than its default.
class _WrapperMarker extends StatelessWidget {
  const _WrapperMarker({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KaiselPageWrapperContext (simple pipeline)', () {
    testWidgets('captures route, position, stackLength, previous, isTop', (
      tester,
    ) async {
      final router = KaiselRouter<_R>(initial: const _A());
      await router.push(const _B());
      await router.push(const _C('1'));

      final captured = <KaiselPageWrapperContext<_R>>[];

      final delegate = KaiselRouterDelegate<_R>(
        router: router,
        builder: (context, route) => Text('$route'),
        pageWrapper: (ctx) {
          captured.add(ctx);
          return MaterialPage<Object?>(key: ctx.key, child: ctx.child);
        },
      );
      addTearDown(delegate.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          routerDelegate: delegate,
          routeInformationParser: _Parser(router),
        ),
      );
      await tester.pumpAndSettle();

      // Three pages: A, B, C('1'). The wrapper is called once per
      // page on each build. With the initial build we should see
      // three contexts in order from bottom (position 0) to top
      // (position 2).
      expect(captured, hasLength(greaterThanOrEqualTo(3)));
      // Take the most recent build's invocations: the last 3.
      final lastBuild = captured.sublist(captured.length - 3);

      expect(lastBuild[0].route, const _A());
      expect(lastBuild[0].position, 0);
      expect(lastBuild[0].stackLength, 3);
      expect(lastBuild[0].previous, isNull);
      expect(lastBuild[0].isBottom, isTrue);
      expect(lastBuild[0].isTop, isFalse);

      expect(lastBuild[1].route, const _B());
      expect(lastBuild[1].position, 1);
      expect(lastBuild[1].stackLength, 3);
      expect(lastBuild[1].previous, const _A());
      expect(lastBuild[1].isBottom, isFalse);
      expect(lastBuild[1].isTop, isFalse);

      expect(lastBuild[2].route, const _C('1'));
      expect(lastBuild[2].position, 2);
      expect(lastBuild[2].stackLength, 3);
      expect(lastBuild[2].previous, const _B());
      expect(lastBuild[2].isBottom, isFalse);
      expect(lastBuild[2].isTop, isTrue);
    });
  });

  group('KaiselPageWrapperContext (adaptive pipeline with absorption)', () {
    testWidgets('previous refers to the rendered-below page, not the absorbed '
        'entry', (tester) async {
      // Stack: [_A, _B, _C('x')]. Adaptive builder absorbs (_C with
      // prev _B) into one page. The bottom page should be A; the
      // absorbing page above should report previous = _A (the page
      // below in the rendered stack), not _B (the absorbed entry).
      final router = KaiselRouter<_R>(initial: const _A());
      await router.push(const _B());
      await router.push(const _C('x'));

      final captured = <KaiselPageWrapperContext<_R>>[];

      final delegate = KaiselRouterDelegate<_R>.adaptive(
        router: router,
        builder: (context, route, stack) {
          return switch ((route, stack.previous)) {
            (_C(), _B()) => const KaiselAbsorbingPage(
              widget: Text('absorbed'),
              absorbing: 1,
            ),
            _ => KaiselStandalonePage(Text('$route')),
          };
        },
        pageWrapper: (ctx) {
          captured.add(ctx);
          return MaterialPage<Object?>(key: ctx.key, child: ctx.child);
        },
      );
      addTearDown(delegate.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          routerDelegate: delegate,
          routeInformationParser: _Parser(router),
        ),
      );
      await tester.pumpAndSettle();

      // After absorption the rendered pages list has TWO pages: A
      // at the bottom, and the absorbing page on top. The wrapper
      // is called once per page on each build.
      expect(captured, hasLength(greaterThanOrEqualTo(2)));
      final lastBuild = captured.sublist(captured.length - 2);

      expect(lastBuild[0].route, const _A());
      expect(lastBuild[0].position, 0);
      expect(lastBuild[0].stackLength, 2);
      expect(lastBuild[0].previous, isNull);

      // Top rendered page: the absorbing entry's route (_C('x')).
      // previous is _A (the rendered page below), NOT _B (which got
      // absorbed). stackLength is 2 (only two rendered pages, even
      // though the router has three entries).
      expect(lastBuild[1].route, const _C('x'));
      expect(lastBuild[1].position, 1);
      expect(lastBuild[1].stackLength, 2);
      expect(lastBuild[1].previous, const _A());
      expect(lastBuild[1].isTop, isTrue);
    });
  });

  group('KaiselBranch pageWrapper (inner navigator)', () {
    testWidgets('a branch pageWrapper wraps the initial page', (tester) async {
      // A two-branch shell where the home branch supplies a custom
      // pageWrapper. The inner navigator must route the branch's
      // initial page through that wrapper (the _wrapSimple `if
      // (wrapper != null)` path), so the marker is in the tree.
      final home = KaiselRouter<_R>(initial: const _A());
      final tab = KaiselRouter<_Tab>(initial: const _TabRoot());
      final shell = BranchedShellRouter(branches: [home, tab]);
      addTearDown(shell.dispose);
      addTearDown(home.dispose);
      addTearDown(tab.dispose);

      var wrapperCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: KaiselBranchedShell(
            shell: shell,
            branches: [
              KaiselBranch<_R>(
                router: home,
                pageBuilder: (context, route) =>
                    Scaffold(body: Text('home:$route')),
                pageWrapper: (ctx) {
                  wrapperCalls++;
                  return MaterialPage<Object?>(
                    key: ctx.key,
                    child: _WrapperMarker(
                      key: const ValueKey('branch-wrapper'),
                      child: ctx.child,
                    ),
                  );
                },
              ),
              KaiselBranch<_Tab>(
                router: tab,
                pageBuilder: (context, route) =>
                    const Scaffold(body: Text('tab')),
              ),
            ],
            chromeBuilder: (context, active, branchContent, switchBranch) =>
                branchContent,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(wrapperCalls, greaterThan(0));
      expect(find.byKey(const ValueKey('branch-wrapper')), findsOneWidget);
      expect(find.text('home:${const _A()}'), findsOneWidget);
    });

    testWidgets('a branch pageWrapper wraps a pushed page too', (tester) async {
      final home = KaiselRouter<_R>(initial: const _A());
      final tab = KaiselRouter<_Tab>(initial: const _TabRoot());
      final shell = BranchedShellRouter(branches: [home, tab]);
      addTearDown(shell.dispose);
      addTearDown(home.dispose);
      addTearDown(tab.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: KaiselBranchedShell(
            shell: shell,
            branches: [
              KaiselBranch<_R>(
                router: home,
                pageBuilder: (context, route) =>
                    Scaffold(body: Text('home:$route')),
                pageWrapper: (ctx) => MaterialPage<Object?>(
                  key: ctx.key,
                  child: _WrapperMarker(
                    // A per-position key so we can count how many
                    // pages went through the wrapper.
                    key: ValueKey('branch-wrapper-${ctx.position}'),
                    child: ctx.child,
                  ),
                ),
              ),
              KaiselBranch<_Tab>(
                router: tab,
                pageBuilder: (context, route) =>
                    const Scaffold(body: Text('tab')),
              ),
            ],
            chromeBuilder: (context, active, branchContent, switchBranch) =>
                branchContent,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('branch-wrapper-0')), findsOneWidget);

      await home.push(const _B());
      await tester.pumpAndSettle();

      // Both the bottom (_A) and the pushed top (_B) pages went
      // through the branch's wrapper. The bottom page is offstage
      // once _B covers it, so look past offstage for it.
      expect(
        find.byKey(const ValueKey('branch-wrapper-0'), skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('branch-wrapper-1')), findsOneWidget);
      expect(find.text('home:${const _B()}'), findsOneWidget);
    });
  });
}
