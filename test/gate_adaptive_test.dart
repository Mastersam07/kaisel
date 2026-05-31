import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gate/gate.dart';

// Test fixtures.

sealed class _AppRoute extends GateRoute {
  const _AppRoute();
}

final class _Home extends _AppRoute {
  const _Home();
}

final class _ProductList extends _AppRoute {
  const _ProductList();
}

final class _ProductDetail extends _AppRoute {
  const _ProductDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

final class _Reviews extends _AppRoute {
  const _Reviews(this.productId);
  final String productId;
  @override
  List<Object?> get props => [productId];
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();
  @override
  Widget build(BuildContext context) => const Text('Home');
}

class _ListScreen extends StatelessWidget {
  const _ListScreen();
  @override
  Widget build(BuildContext context) => const Text('List');
}

class _DetailScreen extends StatelessWidget {
  const _DetailScreen(this.id);
  final String id;
  @override
  Widget build(BuildContext context) => Text('Detail $id');
}

class _ReviewsScreen extends StatelessWidget {
  const _ReviewsScreen(this.productId);
  final String productId;
  @override
  Widget build(BuildContext context) => Text('Reviews $productId');
}

class _AbsorbedMasterDetail extends StatelessWidget {
  const _AbsorbedMasterDetail(this.detailId);
  final String detailId;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          const Text('List'),
          Text('Detail $detailId'),
          const Text('SIDE-BY-SIDE'),
        ],
      );
}

Widget _wrapApp(GateRouterDelegate<_AppRoute> delegate) {
  return MaterialApp.router(
    routerDelegate: delegate,
    routeInformationParser: _CurrentStackParser(delegate.router),
  );
}

class _CurrentStackParser
    extends RouteInformationParser<GateConfig<_AppRoute>> {
  _CurrentStackParser(this.router);

  final GateRouter<_AppRoute> router;

  @override
  Future<GateConfig<_AppRoute>> parseRouteInformation(
    RouteInformation routeInformation,
  ) async =>
      GateConfig<_AppRoute>(mainStack: router.stack);
}

void main() {
  // The adaptive iteration is run during build(), which goes through
  // SchedulerBinding. Tests that touch a delegate need a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GateStackContext', () {
    test('previous and next reflect neighbour positions', () {
      const stack = <_AppRoute>[_Home(), _ProductList(), _ProductDetail('42')];

      final bottom = GateStackContext<_AppRoute>(stack: stack, position: 0);
      expect(bottom.previous, isNull);
      expect(bottom.next, const _ProductList());
      expect(bottom.isBottom, isTrue);
      expect(bottom.isTop, isFalse);

      final middle = GateStackContext<_AppRoute>(stack: stack, position: 1);
      expect(middle.previous, const _Home());
      expect(middle.next, const _ProductDetail('42'));
      expect(middle.isBottom, isFalse);
      expect(middle.isTop, isFalse);

      final top = GateStackContext<_AppRoute>(stack: stack, position: 2);
      expect(top.previous, const _ProductList());
      expect(top.next, isNull);
      expect(top.isBottom, isFalse);
      expect(top.isTop, isTrue);
    });

    test('single-entry stack is both top and bottom', () {
      const stack = <_AppRoute>[_Home()];
      final ctx = GateStackContext<_AppRoute>(stack: stack, position: 0);
      expect(ctx.previous, isNull);
      expect(ctx.next, isNull);
      expect(ctx.isTop, isTrue);
      expect(ctx.isBottom, isTrue);
    });
  });

  group('GatePageResult', () {
    test('GateStandalonePage exposes its widget', () {
      const page = GateStandalonePage(_HomeScreen());
      expect(page.widget, isA<_HomeScreen>());
    });

    test('GateAbsorbingPage exposes widget and absorbing count', () {
      const page = GateAbsorbingPage(
        widget: _AbsorbedMasterDetail('42'),
        absorbing: 2,
      );
      expect(page.widget, isA<_AbsorbedMasterDetail>());
      expect(page.absorbing, 2);
    });

    test('GateAbsorbingPage defaults absorbing to 1', () {
      const page = GateAbsorbingPage(widget: _AbsorbedMasterDetail('1'));
      expect(page.absorbing, 1);
    });

    test('GateAbsorbingPage rejects absorbing < 1 in checked builds', () {
      expect(
        () => GateAbsorbingPage(
          widget: const _AbsorbedMasterDetail('x'),
          absorbing: 0,
        ),
        throwsAssertionError,
      );
    });

    test('GatePageResult is sealed with two known shapes', () {
      // Exhaustive switch compiles and is reachable.
      const GatePageResult page = GateStandalonePage(_HomeScreen());
      final tag = switch (page) {
        GateStandalonePage() => 'standalone',
        GateAbsorbingPage() => 'absorbing',
      };
      expect(tag, 'standalone');
    });
  });

  group('Adaptive rendering: standalone-only', () {
    testWidgets('renders one page per stack entry when all are standalone',
        (tester) async {
      final router = GateRouter<_AppRoute>(initial: const _Home());
      await router.push(const _ProductList());

      final delegate = GateRouterDelegate<_AppRoute>.adaptive(
        router: router,
        builder: (context, route, stack) => GateStandalonePage(
          switch (route) {
            _Home() => const _HomeScreen(),
            _ProductList() => const _ListScreen(),
            _ProductDetail(:final id) => _DetailScreen(id),
            _Reviews(:final productId) => _ReviewsScreen(productId),
          },
        ),
      );
      addTearDown(delegate.dispose);

      await tester.pumpWidget(_wrapApp(delegate));
      await tester.pumpAndSettle();

      // The top page is _ListScreen; _HomeScreen exists in the tree
      // below it (offstage) but isn't visible. The text widget for
      // List is found, and List is the focused content.
      expect(find.text('List'), findsOneWidget);
    });
  });

  group('Adaptive rendering: absorbing', () {
    testWidgets('detail absorbing list collapses two entries into one page',
        (tester) async {
      final router = GateRouter<_AppRoute>(initial: const _ProductList());
      await router.push(const _ProductDetail('42'));

      final delegate = GateRouterDelegate<_AppRoute>.adaptive(
        router: router,
        builder: (context, route, stack) {
          return switch ((route, stack.previous)) {
            (_ProductDetail(:final id), _ProductList()) => GateAbsorbingPage(
                widget: _AbsorbedMasterDetail(id),
                absorbing: 1,
              ),
            (_ProductDetail(:final id), _) => GateStandalonePage(
                _DetailScreen(id),
              ),
            (_ProductList(), _) => const GateStandalonePage(_ListScreen()),
            (_Home(), _) => const GateStandalonePage(_HomeScreen()),
            (_Reviews(:final productId), _) =>
              GateStandalonePage(_ReviewsScreen(productId)),
          };
        },
      );
      addTearDown(delegate.dispose);

      await tester.pumpWidget(_wrapApp(delegate));
      await tester.pumpAndSettle();

      // The absorbed master-detail widget appears, but neither of the
      // individual standalone screens (_ListScreen, _DetailScreen) is
      // rendered, because the absorbing widget replaced both.
      expect(find.byType(_AbsorbedMasterDetail), findsOneWidget);
      expect(find.byType(_ListScreen), findsNothing);
      expect(find.byType(_DetailScreen), findsNothing);
      // The SIDE-BY-SIDE marker text is visible because the absorbed
      // widget renders its own composite layout.
      expect(find.text('SIDE-BY-SIDE'), findsOneWidget);
    });

    testWidgets('absorbing N=2 collapses three entries into one page',
        (tester) async {
      final router = GateRouter<_AppRoute>(initial: const _Home());
      await router.push(const _ProductList());
      await router.push(const _ProductDetail('7'));

      final delegate = GateRouterDelegate<_AppRoute>.adaptive(
        router: router,
        builder: (context, route, stack) {
          // Detail absorbs both ProductList and Home below it.
          if (route is _ProductDetail && stack.position == 2) {
            return GateAbsorbingPage(
              widget: _AbsorbedMasterDetail(route.id),
              absorbing: 2,
            );
          }
          return GateStandalonePage(
            switch (route) {
              _Home() => const _HomeScreen(),
              _ProductList() => const _ListScreen(),
              _ProductDetail(:final id) => _DetailScreen(id),
              _Reviews(:final productId) => _ReviewsScreen(productId),
            },
          );
        },
      );
      addTearDown(delegate.dispose);

      await tester.pumpWidget(_wrapApp(delegate));
      await tester.pumpAndSettle();

      // The single absorbing widget is the only main-stack content.
      expect(find.byType(_AbsorbedMasterDetail), findsOneWidget);
      expect(find.byType(_HomeScreen), findsNothing);
      expect(find.byType(_ListScreen), findsNothing);
    });

    testWidgets(
      'entries above an absorbing entry still render their own pages',
      (tester) async {
        // Stack: [List, Detail, Reviews]
        // Adaptive: Detail absorbs List (1 below). Reviews stays on top
        // as its own page above the absorbed pair.
        final router = GateRouter<_AppRoute>(initial: const _ProductList());
        await router.push(const _ProductDetail('42'));
        await router.push(const _Reviews('42'));

        final delegate = GateRouterDelegate<_AppRoute>.adaptive(
          router: router,
          builder: (context, route, stack) {
            return switch ((route, stack.previous)) {
              (_ProductDetail(:final id), _ProductList()) => GateAbsorbingPage(
                  widget: _AbsorbedMasterDetail(id),
                  absorbing: 1,
                ),
              (_ProductDetail(:final id), _) => GateStandalonePage(
                  _DetailScreen(id),
                ),
              (_ProductList(), _) => const GateStandalonePage(_ListScreen()),
              (_Home(), _) => const GateStandalonePage(_HomeScreen()),
              (_Reviews(:final productId), _) => GateStandalonePage(
                  _ReviewsScreen(productId),
                ),
            };
          },
        );
        addTearDown(delegate.dispose);

        await tester.pumpWidget(_wrapApp(delegate));
        await tester.pumpAndSettle();

        // Reviews is on top, rendered standalone.
        expect(find.text('Reviews 42'), findsOneWidget);
      },
    );
  });

  group('Adaptive rendering: pop semantics', () {
    testWidgets(
      'popping an absorbing page pops the TOP entry, not the lowest absorbed',
      (tester) async {
        final router = GateRouter<_AppRoute>(initial: const _ProductList());
        await router.push(const _ProductDetail('42'));

        final delegate = GateRouterDelegate<_AppRoute>.adaptive(
          router: router,
          builder: (context, route, stack) {
            return switch ((route, stack.previous)) {
              (_ProductDetail(:final id), _ProductList()) => GateAbsorbingPage(
                  widget: _AbsorbedMasterDetail(id),
                  absorbing: 1,
                ),
              (_ProductDetail(:final id), _) =>
                GateStandalonePage(_DetailScreen(id)),
              (_ProductList(), _) => const GateStandalonePage(_ListScreen()),
              (_Home(), _) => const GateStandalonePage(_HomeScreen()),
              (_Reviews(:final productId), _) =>
                GateStandalonePage(_ReviewsScreen(productId)),
            };
          },
        );
        addTearDown(delegate.dispose);

        await tester.pumpWidget(_wrapApp(delegate));
        await tester.pumpAndSettle();

        expect(router.stack, [
          const _ProductList(),
          const _ProductDetail('42'),
        ]);

        // Simulate a Navigator pop (e.g., OS back). The Navigator
        // removes its top page, which triggers onDidRemovePage with
        // the absorbing page. We want the router to pop the TOP entry
        // (_ProductDetail), leaving [_ProductList].
        delegate.navigatorKey.currentState!.maybePop();
        await tester.pumpAndSettle();

        expect(
          router.stack,
          [const _ProductList()],
          reason: 'pop should remove the top entry, not the absorbed one',
        );
      },
    );
  });

  group('Adaptive rendering: master-detail item swap', () {
    testWidgets(
      'replacing the detail entry preserves Navigator page identity',
      (tester) async {
        // Master-detail at wide breakpoint. Swapping detail-A for
        // detail-B should not trigger a Navigator transition. We
        // verify this indirectly: after the swap, the absorbed
        // widget instance changes content but the same widget type
        // is on screen the whole way through.
        final router = GateRouter<_AppRoute>(initial: const _ProductList());
        await router.push(const _ProductDetail('A'));

        final delegate = GateRouterDelegate<_AppRoute>.adaptive(
          router: router,
          builder: (context, route, stack) {
            return switch ((route, stack.previous)) {
              (_ProductDetail(:final id), _ProductList()) => GateAbsorbingPage(
                  widget: _AbsorbedMasterDetail(id),
                  absorbing: 1,
                ),
              (_ProductDetail(:final id), _) =>
                GateStandalonePage(_DetailScreen(id)),
              (_ProductList(), _) => const GateStandalonePage(_ListScreen()),
              (_Home(), _) => const GateStandalonePage(_HomeScreen()),
              (_Reviews(:final productId), _) =>
                GateStandalonePage(_ReviewsScreen(productId)),
            };
          },
        );
        addTearDown(delegate.dispose);

        await tester.pumpWidget(_wrapApp(delegate));
        await tester.pumpAndSettle();
        expect(find.text('Detail A'), findsOneWidget);

        // Swap detail-A for detail-B via replace at the top.
        await router.replace(const _ProductDetail('B'));
        await tester.pumpAndSettle();

        // New detail content visible; absorbed widget still the only
        // main-stack page rendered.
        expect(find.text('Detail B'), findsOneWidget);
        expect(find.text('Detail A'), findsNothing);
        expect(find.byType(_AbsorbedMasterDetail), findsOneWidget);
      },
    );
  });

  group('Adaptive rendering: degrades to simple when no absorbing', () {
    testWidgets(
      'an adaptive builder that always returns standalone behaves like the '
      'simple pipeline',
      (tester) async {
        final router = GateRouter<_AppRoute>(initial: const _Home());
        await router.push(const _ProductList());
        await router.push(const _ProductDetail('42'));

        final delegate = GateRouterDelegate<_AppRoute>.adaptive(
          router: router,
          builder: (context, route, stack) => GateStandalonePage(
            switch (route) {
              _Home() => const _HomeScreen(),
              _ProductList() => const _ListScreen(),
              _ProductDetail(:final id) => _DetailScreen(id),
              _Reviews(:final productId) => _ReviewsScreen(productId),
            },
          ),
        );
        addTearDown(delegate.dispose);

        await tester.pumpWidget(_wrapApp(delegate));
        await tester.pumpAndSettle();

        // Top page visible.
        expect(find.text('Detail 42'), findsOneWidget);

        // Pop reveals the previous page.
        delegate.navigatorKey.currentState!.maybePop();
        await tester.pumpAndSettle();
        expect(router.stack, [const _Home(), const _ProductList()]);
        expect(find.text('List'), findsOneWidget);
      },
    );
  });

  group('GateMasterDetailScaffold', () {
    testWidgets('renders master and detail side by side', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GateMasterDetailScaffold(
              master: Text('LEFT'),
              detail: Text('RIGHT'),
            ),
          ),
        ),
      );

      expect(find.text('LEFT'), findsOneWidget);
      expect(find.text('RIGHT'), findsOneWidget);
    });

    test('rejects masterFraction outside (0, 1)', () {
      expect(
        () => GateMasterDetailScaffold(
          master: const SizedBox(),
          detail: const SizedBox(),
          masterFraction: 0,
        ),
        throwsAssertionError,
      );
      expect(
        () => GateMasterDetailScaffold(
          master: const SizedBox(),
          detail: const SizedBox(),
          masterFraction: 1,
        ),
        throwsAssertionError,
      );
    });
  });
}
