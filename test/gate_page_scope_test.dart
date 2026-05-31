import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gate/gate.dart';

// Test routes.
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

/// Reads the scope from its context and forwards it to a builder
/// so widget tests can assert on the values seen by descendants.
class _ScopeReader extends StatelessWidget {
  const _ScopeReader({required this.onBuild});

  final void Function(GatePageScope? scope) onBuild;

  @override
  Widget build(BuildContext context) {
    final scope = GatePageScope.maybeOf(context);
    onBuild(scope);
    return const Scaffold(body: SizedBox.shrink());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GatePageScope (simple pipeline)', () {
    testWidgets('descendant sees the page\'s navigation context',
        (tester) async {
      final router = GateRouter<_R>(initial: const _A());
      await router.push(const _B());
      await router.push(const _C('1'));

      final readings = <(GateRoute, int, int, GateRoute?)>[];

      final delegate = GateRouterDelegate<_R>(
        router: router,
        builder: (context, route) => _ScopeReader(
          onBuild: (scope) {
            if (scope == null) return;
            readings.add(
              (
                scope.route,
                scope.position,
                scope.stackLength,
                scope.previous,
              ),
            );
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
      final router = GateRouter<_R>(initial: const _A());

      bool? observedIsBottom;
      bool? observedIsTop;

      final delegate = GateRouterDelegate<_R>(
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

  group('GatePageScope (adaptive pipeline)', () {
    testWidgets(
        'absorbing pages report isBottom=true even when the '
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

      final router = GateRouter<_R>(initial: const _A());
      await router.push(const _C('x'));
      // Stack: [_A, _C('x')]. Adaptive builder absorbs (_C with
      // prev _A) into one page. Rendered Navigator has ONE page:
      // the absorbing one. Inside it, isBottom should be true.

      GatePageScope? observed;

      final delegate = GateRouterDelegate<_R>.adaptive(
        router: router,
        builder: (context, route, stack) {
          return switch ((route, stack.previous)) {
            (_C(), _A()) => GateAbsorbingPage(
                widget: _ScopeReader(
                  onBuild: (scope) => observed = scope,
                ),
                absorbing: 1,
              ),
            _ => GateStandalonePage(
                _ScopeReader(
                  onBuild: (scope) => observed = scope,
                ),
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

  group('GatePageScope.maybeOf / of', () {
    testWidgets('maybeOf returns null outside a gate page', (tester) async {
      GatePageScope? observed;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              observed = GatePageScope.maybeOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(observed, isNull);
    });

    testWidgets('updateShouldNotify fires when context fields change',
        (tester) async {
      // Push to make position/stackLength change, then verify the
      // dependent rebuilt.
      final router = GateRouter<_R>(initial: const _A());
      var buildCount = 0;

      final delegate = GateRouterDelegate<_R>(
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
