import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// Test routes.
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

/// Reads the scope from its context and forwards it to a builder
/// so widget tests can assert on the values seen by descendants.
class _ScopeReader extends StatelessWidget {
  const _ScopeReader({required this.onBuild});

  final void Function(KaiselPageScope? scope) onBuild;

  @override
  Widget build(BuildContext context) {
    final scope = KaiselPageScope.maybeOf(context);
    onBuild(scope);
    return const Scaffold(body: SizedBox.shrink());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KaiselPageScope (simple pipeline)', () {
    testWidgets('descendant sees the page\'s navigation context', (
      tester,
    ) async {
      final router = KaiselRouter<_R>(initial: const _A());
      await router.push(const _B());
      await router.push(const _C('1'));

      final readings = <(KaiselRoute, int, int, KaiselRoute?)>[];

      final delegate = KaiselRouterDelegate<_R>(
        router: router,
        builder: (context, route) => _ScopeReader(
          onBuild: (scope) {
            if (scope == null) return;
            readings.add((
              scope.route,
              scope.position,
              scope.stackLength,
              scope.previous,
            ));
          },
        ),
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

      // The top page (C) is the one currently visible to the
      // widget tester, so the latest reading should be C's scope.
      expect(readings, isNotEmpty);
      final latest = readings.last;
      expect(latest.$1, const _C('1'));
      expect(latest.$2, 2);
      expect(latest.$3, 3);
      expect(latest.$4, const _B());
    });

    testWidgets('isBottom is true for the only rendered page', (tester) async {
      final router = KaiselRouter<_R>(initial: const _A());

      bool? observedIsBottom;
      bool? observedIsTop;

      final delegate = KaiselRouterDelegate<_R>(
        router: router,
        builder: (context, route) => _ScopeReader(
          onBuild: (scope) {
            if (scope == null) return;
            observedIsBottom = scope.isBottom;
            observedIsTop = scope.isTop;
          },
        ),
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

      expect(observedIsBottom, isTrue);
      expect(observedIsTop, isTrue);
    });
  });

  group('KaiselPageScope (adaptive pipeline)', () {
    testWidgets('absorbing pages report isBottom=true even when the '
        'router stack has multiple entries', (tester) async {
      // Stack: [_A, _B, _C('x')]. Adaptive builder absorbs _C+_B
      // into one page. After absorption, the rendered Navigator has
      // pages [_A, absorbing(_B+_C)]. The absorbing page is at
      // rendered position 1, stackLength 2.
      //
      // Inside the absorbing page's widget tree, descendants see
      // the absorbing page's scope: route=_C, position=1,
      // stackLength=2, previous=_A. isBottom=false because there's
      // _A below.
      //
      // Now we'll test the more interesting case: a stack where the
      // absorbing page is THE ONLY rendered page.

      final router = KaiselRouter<_R>(initial: const _A());
      await router.push(const _C('x'));
      // Stack: [_A, _C('x')]. Adaptive builder absorbs (_C with
      // prev _A) into one page. Rendered Navigator has ONE page:
      // the absorbing one. Inside it, isBottom should be true.

      KaiselPageScope? observed;

      final delegate = KaiselRouterDelegate<_R>.adaptive(
        router: router,
        builder: (context, route, stack) {
          return switch ((route, stack.previous)) {
            (_C(), _A()) => KaiselAbsorbingPage(
              widget: _ScopeReader(onBuild: (scope) => observed = scope),
              absorbing: 1,
            ),
            _ => KaiselStandalonePage(
              _ScopeReader(onBuild: (scope) => observed = scope),
            ),
          };
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

      expect(observed, isNotNull);
      // The absorbing page absorbed _A below, so the rendered
      // Navigator has only ONE page total. Inside that page, the
      // descendant should see isBottom=true.
      expect(observed!.route, const _C('x'));
      expect(observed!.position, 0);
      expect(observed!.stackLength, 1);
      expect(observed!.previous, isNull);
      expect(observed!.isBottom, isTrue);
      expect(observed!.isTop, isTrue);
    });
  });

  group('KaiselPageScope.maybeOf / of', () {
    testWidgets('maybeOf returns null outside a kaisel page', (tester) async {
      KaiselPageScope? observed;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              observed = KaiselPageScope.maybeOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(observed, isNull);
    });

    testWidgets('updateShouldNotify fires when context fields change', (
      tester,
    ) async {
      // Push to make position/stackLength change, then verify the
      // dependent rebuilt.
      final router = KaiselRouter<_R>(initial: const _A());
      var buildCount = 0;

      final delegate = KaiselRouterDelegate<_R>(
        router: router,
        builder: (context, route) => _ScopeReader(
          onBuild: (scope) {
            if (scope?.route == const _A()) buildCount++;
          },
        ),
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

      final beforePush = buildCount;
      await router.push(const _B());
      await tester.pumpAndSettle();

      // The _A page's scope went from (position=0, stackLength=1)
      // to (position=0, stackLength=2). updateShouldNotify should
      // fire on stackLength change, rebuilding the dependent.
      expect(buildCount, greaterThan(beforePush));
    });
  });
}
