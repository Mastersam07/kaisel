import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gate/gate.dart';

// Routes for testing wrapper context.
sealed class _R extends GateRoute {
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

class _Parser extends RouteInformationParser<GateConfig<_R>> {
  _Parser(this.router);
  final GateRouter<_R> router;
  @override
  Future<GateConfig<_R>> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    return GateConfig<_R>(mainStack: router.stack);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GatePageWrapperContext (simple pipeline)', () {
    testWidgets('captures route, position, stackLength, previous, isTop', (
      tester,
    ) async {
      final router = GateRouter<_R>(initial: const _A());
      await router.push(const _B());
      await router.push(const _C('1'));

      // Record every wrapper call so the test can inspect them.
      final captured = <GatePageWrapperContext<_R>>[];

      final delegate = GateRouterDelegate<_R>(
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

      // Bottom: A
      expect(lastBuild[0].route, const _A());
      expect(lastBuild[0].position, 0);
      expect(lastBuild[0].stackLength, 3);
      expect(lastBuild[0].previous, isNull);
      expect(lastBuild[0].isBottom, isTrue);
      expect(lastBuild[0].isTop, isFalse);

      // Middle: B
      expect(lastBuild[1].route, const _B());
      expect(lastBuild[1].position, 1);
      expect(lastBuild[1].stackLength, 3);
      expect(lastBuild[1].previous, const _A());
      expect(lastBuild[1].isBottom, isFalse);
      expect(lastBuild[1].isTop, isFalse);

      // Top: C('1')
      expect(lastBuild[2].route, const _C('1'));
      expect(lastBuild[2].position, 2);
      expect(lastBuild[2].stackLength, 3);
      expect(lastBuild[2].previous, const _B());
      expect(lastBuild[2].isBottom, isFalse);
      expect(lastBuild[2].isTop, isTrue);
    });
  });

  group('GatePageWrapperContext (adaptive pipeline with absorption)', () {
    testWidgets('previous refers to the rendered-below page, not the absorbed '
        'entry', (tester) async {
      // Stack: [_A, _B, _C('x')]. Adaptive builder absorbs (_C with
      // prev _B) into one page. The bottom page should be A; the
      // absorbing page above should report previous = _A (the page
      // below in the rendered stack), not _B (the absorbed entry).
      final router = GateRouter<_R>(initial: const _A());
      await router.push(const _B());
      await router.push(const _C('x'));

      final captured = <GatePageWrapperContext<_R>>[];

      final delegate = GateRouterDelegate<_R>.adaptive(
        router: router,
        builder: (context, route, stack) {
          return switch ((route, stack.previous)) {
            (_C(), _B()) => const GateAbsorbingPage(
              widget: Text('absorbed'),
              absorbing: 1,
            ),
            _ => GateStandalonePage(Text('$route')),
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

      // Bottom rendered page: A.
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
}
