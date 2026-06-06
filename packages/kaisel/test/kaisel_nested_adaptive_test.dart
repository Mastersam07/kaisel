import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';
import 'package:kaisel/src/kaisel_adaptive.dart'
    show KaiselAdaptiveKey, adaptiveEntryIdFromPageKey;

// Test fixtures: two separate route hierarchies, one per branch.

sealed class _HomeRoute extends KaiselRoute {
  const _HomeRoute();
}

final class _HomeRoot extends _HomeRoute {
  const _HomeRoot();
}

final class _HomeList extends _HomeRoute {
  const _HomeList();
}

final class _HomeDetail extends _HomeRoute {
  const _HomeDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

sealed class _DiscoverRoute extends KaiselRoute {
  const _DiscoverRoute();
}

final class _DiscoverRoot extends _DiscoverRoute {
  const _DiscoverRoot();
}

// A module route hierarchy for the module-adaptive tests.

sealed class _ShopRoute extends KaiselRoute {
  const _ShopRoute();
}

final class _ShopList extends _ShopRoute {
  const _ShopList();
}

final class _ShopDetail extends _ShopRoute {
  const _ShopDetail(this.sku);
  final String sku;
  @override
  List<Object?> get props => [sku];
}

// Top-level app route to drive the host delegate.

sealed class _AppRoute extends KaiselRoute {
  const _AppRoute();
}

final class _AppHome extends _AppRoute {
  const _AppHome();
}

final class _AppShop extends _AppRoute {
  const _AppShop();
}

class _HomeRootScreen extends StatelessWidget {
  const _HomeRootScreen();
  @override
  Widget build(BuildContext context) => const Text('HomeRoot');
}

class _HomeListScreen extends StatelessWidget {
  const _HomeListScreen();
  @override
  Widget build(BuildContext context) => const Text('HomeList');
}

class _HomeDetailScreen extends StatelessWidget {
  const _HomeDetailScreen(this.id);
  final String id;
  @override
  Widget build(BuildContext context) => Text('HomeDetail $id');
}

class _DiscoverRootScreen extends StatelessWidget {
  const _DiscoverRootScreen();
  @override
  Widget build(BuildContext context) => const Text('DiscoverRoot');
}

class _AbsorbedHome extends StatelessWidget {
  const _AbsorbedHome(this.detailId);
  final String detailId;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Text('HomeList'),
      Text('HomeDetail $detailId'),
      const Text('ABSORBED-HOME'),
    ],
  );
}

class _ShopListScreen extends StatelessWidget {
  const _ShopListScreen();
  @override
  Widget build(BuildContext context) => const Text('ShopList');
}

class _ShopDetailScreen extends StatelessWidget {
  const _ShopDetailScreen(this.sku);
  final String sku;
  @override
  Widget build(BuildContext context) => Text('ShopDetail $sku');
}

class _AbsorbedShop extends StatelessWidget {
  const _AbsorbedShop(this.sku);
  final String sku;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Text('ShopList'),
      Text('ShopDetail $sku'),
      const Text('ABSORBED-SHOP'),
    ],
  );
}

class _AppHomeScreen extends StatelessWidget {
  const _AppHomeScreen({required this.shell, required this.branches});
  final BranchedShellRouter shell;
  final List<KaiselBranch> branches;
  @override
  Widget build(BuildContext context) {
    return KaiselBranchedShell(
      shell: shell,
      branches: branches,
      chromeBuilder: (context, active, branchContent, switchBranch) {
        return Scaffold(body: branchContent);
      },
    );
  }
}

// A module that opts into adaptive rendering. At wide widths the
// detail absorbs the list into a single page.
class _AdaptiveShopModule extends RouteModule<_ShopRoute> {
  const _AdaptiveShopModule();

  @override
  List<_ShopRoute> get initialStack => const [_ShopList()];

  @override
  bool get isAdaptive => true;

  @override
  Widget buildPage(BuildContext context, _ShopRoute route) {
    return switch (route) {
      _ShopList() => const _ShopListScreen(),
      _ShopDetail(:final sku) => _ShopDetailScreen(sku),
    };
  }

  @override
  KaiselPageResult buildAdaptivePage(
    BuildContext context,
    _ShopRoute route,
    KaiselStackContext<_ShopRoute> stack,
  ) {
    return switch ((route, stack.previous)) {
      (_ShopDetail(:final sku), _ShopList()) => KaiselAbsorbingPage(
        widget: _AbsorbedShop(sku),
        absorbing: 1,
      ),
      _ => KaiselStandalonePage(buildPage(context, route)),
    };
  }
}

// A module that doesn't override anything; falls back to the default
// adaptive behaviour (every page is standalone, wrapping buildPage).
class _SimpleShopModule extends RouteModule<_ShopRoute> {
  const _SimpleShopModule();

  @override
  List<_ShopRoute> get initialStack => const [_ShopList()];

  @override
  Widget buildPage(BuildContext context, _ShopRoute route) {
    return switch (route) {
      _ShopList() => const _ShopListScreen(),
      _ShopDetail(:final sku) => _ShopDetailScreen(sku),
    };
  }
}

class _CurrentStackParser
    extends RouteInformationParser<KaiselConfig<_AppRoute>> {
  _CurrentStackParser(this.router);
  final KaiselRouter<_AppRoute> router;

  @override
  Future<KaiselConfig<_AppRoute>> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    return KaiselConfig<_AppRoute>(mainStack: router.stack);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Shell adaptive: KaiselBranch.adaptive', () {
    testWidgets(
      'adaptive branch collapses list+detail into one absorbing page',
      (tester) async {
        // Set up the home branch router with [HomeList, HomeDetail].
        // The discover branch is plain.
        final homeRouter = KaiselRouter<_HomeRoute>(initial: const _HomeRoot());
        await homeRouter.push(const _HomeList());
        await homeRouter.push(const _HomeDetail('42'));

        final discoverRouter = KaiselRouter<_DiscoverRoute>(
          initial: const _DiscoverRoot(),
        );

        final shell = BranchedShellRouter(
          branches: [homeRouter, discoverRouter],
        );
        addTearDown(shell.dispose);
        addTearDown(homeRouter.dispose);
        addTearDown(discoverRouter.dispose);

        final mainRouter = KaiselRouter<_AppRoute>(initial: const _AppHome());
        final delegate = KaiselRouterDelegate<_AppRoute>(
          router: mainRouter,
          builder: (context, route) => switch (route) {
            _AppHome() => _AppHomeScreen(
              shell: shell,
              branches: [
                KaiselBranch<_HomeRoute>.adaptive(
                  router: homeRouter,
                  pageBuilder: (context, route, stack) {
                    return switch ((route, stack.previous)) {
                      (_HomeDetail(:final id), _HomeList()) =>
                        KaiselAbsorbingPage(
                          widget: _AbsorbedHome(id),
                          absorbing: 1,
                        ),
                      (_HomeDetail(:final id), _) => KaiselStandalonePage(
                        _HomeDetailScreen(id),
                      ),
                      (_HomeList(), _) => const KaiselStandalonePage(
                        _HomeListScreen(),
                      ),
                      (_HomeRoot(), _) => const KaiselStandalonePage(
                        _HomeRootScreen(),
                      ),
                    };
                  },
                ),
                KaiselBranch<_DiscoverRoute>(
                  router: discoverRouter,
                  pageBuilder: (context, route) => const _DiscoverRootScreen(),
                ),
              ],
            ),
            _AppShop() => const SizedBox.shrink(),
          },
        );
        addTearDown(delegate.dispose);
        addTearDown(mainRouter.dispose);

        await tester.pumpWidget(
          MaterialApp.router(
            routerDelegate: delegate,
            routeInformationParser: _CurrentStackParser(delegate.router),
          ),
        );
        await tester.pumpAndSettle();

        // The absorbed widget is visible; the individual screens for
        // List and Detail are NOT, because adaptive absorption
        // replaced them with one composite widget.
        expect(find.byType(_AbsorbedHome), findsOneWidget);
        expect(find.byType(_HomeListScreen), findsNothing);
        expect(find.byType(_HomeDetailScreen), findsNothing);
        expect(find.text('ABSORBED-HOME'), findsOneWidget);
      },
    );

    testWidgets(
      'popping inside an adaptive branch pops the top entry via PopScope',
      (tester) async {
        // Same setup as above. Verify that triggering the shell's
        // PopScope (the canonical Android-back path inside a shell)
        // pops the top entry from the branch even when absorption
        // has collapsed the visible pages to one.
        final homeRouter = KaiselRouter<_HomeRoute>(initial: const _HomeList());
        await homeRouter.push(const _HomeDetail('42'));

        final shell = BranchedShellRouter(branches: [homeRouter]);
        addTearDown(shell.dispose);
        addTearDown(homeRouter.dispose);

        final mainRouter = KaiselRouter<_AppRoute>(initial: const _AppHome());
        final delegate = KaiselRouterDelegate<_AppRoute>(
          router: mainRouter,
          builder: (context, route) => _AppHomeScreen(
            shell: shell,
            branches: [
              KaiselBranch<_HomeRoute>.adaptive(
                router: homeRouter,
                pageBuilder: (context, route, stack) {
                  return switch ((route, stack.previous)) {
                    (_HomeDetail(:final id), _HomeList()) =>
                      KaiselAbsorbingPage(
                        widget: _AbsorbedHome(id),
                        absorbing: 1,
                      ),
                    (_HomeDetail(:final id), _) => KaiselStandalonePage(
                      _HomeDetailScreen(id),
                    ),
                    (_HomeList(), _) => const KaiselStandalonePage(
                      _HomeListScreen(),
                    ),
                    (_HomeRoot(), _) => const KaiselStandalonePage(
                      _HomeRootScreen(),
                    ),
                  };
                },
              ),
            ],
          ),
        );
        addTearDown(delegate.dispose);
        addTearDown(mainRouter.dispose);

        await tester.pumpWidget(
          MaterialApp.router(
            routerDelegate: delegate,
            routeInformationParser: _CurrentStackParser(delegate.router),
          ),
        );
        await tester.pumpAndSettle();

        expect(homeRouter.stack, [const _HomeList(), const _HomeDetail('42')]);

        // The shell's PopScope reacts to back gestures by calling
        // shell.popCurrent(), which pops the active branch's router
        // directly (bypassing Navigator.maybePop). That path is
        // absorption-safe by construction: it sees the full logical
        // stack and pops its top.
        shell.popCurrent();
        await tester.pumpAndSettle();

        expect(homeRouter.stack, [const _HomeList()]);
      },
    );
  });

  group('Module adaptive: RouteModule.buildAdaptivePage', () {
    testWidgets('an isAdaptive module with stack [List, Detail] renders the '
        'absorbed composite', (tester) async {
      // We can't push from the outside (the module's router is
      // private to the mount), so set up a module whose initialStack
      // is already [List, Detail] to land in the absorbing state.
      const module = _PrePushedAdaptiveShopModule();

      final mainRouter = KaiselRouter<_AppRoute>(initial: const _AppShop());
      final delegate = KaiselRouterDelegate<_AppRoute>(
        router: mainRouter,
        builder: (context, route) => switch (route) {
          _AppShop() => const KaiselModuleMount<_ShopRoute>(module: module),
          _AppHome() => const SizedBox.shrink(),
        },
      );
      addTearDown(delegate.dispose);
      addTearDown(mainRouter.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          routerDelegate: delegate,
          routeInformationParser: _CurrentStackParser(delegate.router),
        ),
      );
      await tester.pumpAndSettle();

      // Absorbing widget is visible; standalone List/Detail screens
      // are not.
      expect(find.byType(_AbsorbedShop), findsOneWidget);
      expect(find.byType(_ShopListScreen), findsNothing);
      expect(find.byType(_ShopDetailScreen), findsNothing);
      expect(find.text('ABSORBED-SHOP'), findsOneWidget);
    });

    testWidgets(
      'a non-adaptive module ignores buildAdaptivePage and renders 1:1',
      (tester) async {
        // _SimpleShopModule doesn't set isAdaptive, so it goes through
        // the simple pipeline even though RouteModule.buildAdaptivePage
        // has a default implementation. Initial stack [ShopList]
        // renders just ShopList.
        const module = _SimpleShopModule();

        final mainRouter = KaiselRouter<_AppRoute>(initial: const _AppShop());
        final delegate = KaiselRouterDelegate<_AppRoute>(
          router: mainRouter,
          builder: (context, route) => switch (route) {
            _AppShop() => const KaiselModuleMount<_ShopRoute>(module: module),
            _AppHome() => const SizedBox.shrink(),
          },
        );
        addTearDown(delegate.dispose);
        addTearDown(mainRouter.dispose);

        await tester.pumpWidget(
          MaterialApp.router(
            routerDelegate: delegate,
            routeInformationParser: _CurrentStackParser(delegate.router),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('ShopList'), findsOneWidget);
      },
    );
  });

  group('RouteModule.buildAdaptivePage default behaviour', () {
    testWidgets(
      'default buildAdaptivePage wraps buildPage as a standalone page',
      (tester) async {
        const module = _SimpleShopModule();
        // The default implementation returns
        // KaiselStandalonePage(buildPage(...)). Call it and verify.
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                final result = module.buildAdaptivePage(
                  context,
                  const _ShopList(),
                  KaiselStackContext<_ShopRoute>(
                    stack: const [_ShopList()],
                    position: 0,
                  ),
                );
                expect(result, isA<KaiselStandalonePage>());
                expect(result.widget, isA<_ShopListScreen>());
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      },
    );

    test('isAdaptive defaults to false', () {
      const module = _SimpleShopModule();
      expect(module.isAdaptive, isFalse);
    });

    test('isAdaptive can be opted in by overriding', () {
      const module = _AdaptiveShopModule();
      expect(module.isAdaptive, isTrue);
    });
  });

  group('adaptiveEntryIdFromPageKey', () {
    test('returns the popId of a KaiselAdaptiveKey', () {
      // stableId and popId differ for absorbing pages; the pop target
      // is the popId, not the stableId.
      const key = KaiselAdaptiveKey(2, 5);
      expect(adaptiveEntryIdFromPageKey(key), 5);
    });

    test('returns the value of a ValueKey<int>', () {
      expect(adaptiveEntryIdFromPageKey(const ValueKey<int>(7)), 7);
    });

    test('returns null for an unrecognised key type', () {
      expect(adaptiveEntryIdFromPageKey(const ValueKey<String>('x')), isNull);
      expect(adaptiveEntryIdFromPageKey(UniqueKey()), isNull);
    });

    test('returns null for a null key', () {
      expect(adaptiveEntryIdFromPageKey(null), isNull);
    });
  });
}

// A module whose initialStack is already at a depth that triggers
// absorption. Used because we can't push into a module's internal
// router from a widget test without grabbing onto its private router.
class _PrePushedAdaptiveShopModule extends RouteModule<_ShopRoute> {
  const _PrePushedAdaptiveShopModule();

  @override
  List<_ShopRoute> get initialStack => const [_ShopList(), _ShopDetail('99')];

  @override
  bool get isAdaptive => true;

  @override
  Widget buildPage(BuildContext context, _ShopRoute route) {
    return switch (route) {
      _ShopList() => const _ShopListScreen(),
      _ShopDetail(:final sku) => _ShopDetailScreen(sku),
    };
  }

  @override
  KaiselPageResult buildAdaptivePage(
    BuildContext context,
    _ShopRoute route,
    KaiselStackContext<_ShopRoute> stack,
  ) {
    return switch ((route, stack.previous)) {
      (_ShopDetail(:final sku), _ShopList()) => KaiselAbsorbingPage(
        widget: _AbsorbedShop(sku),
        absorbing: 1,
      ),
      _ => KaiselStandalonePage(buildPage(context, route)),
    };
  }
}
