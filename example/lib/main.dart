import 'package:flutter/material.dart';
import 'package:gate/gate.dart';

// ─────────────────────────────────────────────────────────────────────
// 1. Routes
//
// In v0.4, each shell branch has its own sealed type. AppRoute contains
// only top-level concerns; HomeRoute / DiscoverRoute / ProfileRoute are
// separate hierarchies. The compiler enforces "you can't push a
// DiscoverRoute into the Home tab."
// ─────────────────────────────────────────────────────────────────────

// Top-level routes (main router).
sealed class AppRoute extends GateRoute {
  const AppRoute();
}

final class Splash extends AppRoute {
  const Splash();
}

final class Login extends AppRoute {
  const Login();
}

abstract interface class RequiresAuth {}

final class MainShell extends AppRoute implements RequiresAuth {
  const MainShell();
}

final class Settings extends AppRoute implements RequiresAuth {
  const Settings();
}

// Modal flow routes — still AppRoute, because flows run on the main
// router and overlay the entire app (including the shell chrome).
final class ConfirmAddToCart extends AppRoute
    implements RequiresAuth, GateModalRoute<int> {
  const ConfirmAddToCart(this.productId);
  final String productId;
  @override
  List<Object?> get props => [productId];
}

final class ConfirmAddToCartReview extends AppRoute implements RequiresAuth {
  const ConfirmAddToCartReview({
    required this.productId,
    required this.quantity,
  });
  final String productId;
  final int quantity;
  @override
  List<Object?> get props => [productId, quantity];
}

// Per-branch sealed hierarchies. Each branch's router is typed to its
// specific subtype.

sealed class HomeRoute extends GateRoute {
  const HomeRoute();
}

final class HomeRoot extends HomeRoute {
  const HomeRoot();
}

final class ProductDetail extends HomeRoute {
  const ProductDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

sealed class DiscoverRoute extends GateRoute {
  const DiscoverRoute();
}

final class DiscoverRoot extends DiscoverRoute {
  const DiscoverRoot();
}

final class FeedItem extends DiscoverRoute {
  const FeedItem(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

sealed class ProfileRoute extends GateRoute {
  const ProfileRoute();
}

final class ProfileRoot extends ProfileRoute {
  const ProfileRoot();
}

// ─────────────────────────────────────────────────────────────────────
// 2. Auth state
// ─────────────────────────────────────────────────────────────────────

class AuthState extends ValueNotifier<bool> {
  AuthState() : super(false);
  void logIn() => value = true;
  void logOut() => value = false;
}

final auth = AuthState();

// ─────────────────────────────────────────────────────────────────────
// 3. Guards (main router only; once you're past MainShell the user is
//    authenticated for the rest of the session, so branch routers
//    don't need their own auth guards in this example).
// ─────────────────────────────────────────────────────────────────────

GateGuard<AppRoute> authGuard(AuthState auth) {
  return (current, proposed) {
    final needsAuth = proposed.any((r) => r is RequiresAuth);
    if (needsAuth && !auth.value) return const [Login()];
    return proposed;
  };
}

GateGuard<AppRoute> splashRedirectGuard(AuthState auth) {
  return (current, proposed) {
    if (proposed.length == 1 && proposed.single is Splash) {
      return [auth.value ? const MainShell() : const Login()];
    }
    return proposed;
  };
}

// ─────────────────────────────────────────────────────────────────────
// 4. URL codec — main router only.
//

class AppStackCodec implements GateStackCodec<AppRoute> {
  const AppStackCodec();

  @override
  Uri encode(List<AppRoute> stack) => switch (stack.last) {
    Splash() => Uri(path: '/'),
    Login() => Uri(path: '/login'),
    MainShell() => Uri(path: '/app'),
    Settings() => Uri(path: '/settings'),
    // Modal flow routes are transient state — not URL-addressable.
    ConfirmAddToCart() || ConfirmAddToCartReview() => Uri(path: '/app'),
  };

  @override
  List<AppRoute>? decode(Uri uri) => switch (uri.pathSegments) {
    [] || [''] => const [Splash()],
    ['login'] => const [Login()],
    ['app'] => const [MainShell()],
    ['settings'] => const [MainShell(), Settings()],
    _ => null,
  };
}

// ─────────────────────────────────────────────────────────────────────
// 5. Wire it up.
//
// The main router is global. Branch routers are created in
// _MainShellScreen's State so they're tied to the shell's lifecycle.
// ─────────────────────────────────────────────────────────────────────

final router = GateRouter<AppRoute>(
  initial: const Splash(),
  guards: [splashRedirectGuard(auth), authGuard(auth)],
);

void main() {
  auth.addListener(() {
    if (!auth.value) router.set(const [Login()]);
  });

  runApp(
    MaterialApp.router(
      title: 'Gate v0.4 example',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      routerDelegate: GateRouterDelegate<AppRoute>(
        router: router,
        builder: _buildMainPage,
        modalBuilder: _buildModal,
      ),
      routeInformationParser: GateRouteInformationParser<AppRoute>(
        codec: const AppStackCodec(),
        fallback: const [Splash()],
      ),
    ),
  );
}

// Main router's pageBuilder — exhaustive over AppRoute (top-level
// routes + modal flow routes). It does NOT handle HomeRoute /
// DiscoverRoute / ProfileRoute — those are each branch's concern.
Widget _buildMainPage(BuildContext context, AppRoute route) => switch (route) {
  Splash() => const _SplashScreen(),
  Login() => const _LoginScreen(),
  MainShell() => const _MainShellScreen(),
  Settings() => const _SettingsScreen(),
  ConfirmAddToCart(:final productId) => _ConfirmAddToCartScreen(
    productId: productId,
  ),
  ConfirmAddToCartReview(:final productId, :final quantity) =>
    _ConfirmAddToCartReviewScreen(productId: productId, quantity: quantity),
};

Widget _buildModal(
  BuildContext context,
  GateModalRoute<Object?> route,
  Widget flowChild,
) {
  return Material(
    color: Colors.black54,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Material(
            clipBehavior: Clip.hardEdge,
            borderRadius: BorderRadius.circular(16),
            child: flowChild,
          ),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────
// 6. Screens
// ─────────────────────────────────────────────────────────────────────

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();
  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      router.replace(const Splash());
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _LoginScreen extends StatelessWidget {
  const _LoginScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Center(
        child: FilledButton(
          onPressed: () {
            auth.logIn();
            router.set(const [MainShell()]);
          },
          child: const Text('Log in'),
        ),
      ),
    );
  }
}

/// Creates branch routers and the shell aggregator, keeps them alive
/// for the lifetime of the main shell, and renders them with
/// `GateBranchedShell`.
class _MainShellScreen extends StatefulWidget {
  const _MainShellScreen();
  @override
  State<_MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<_MainShellScreen> {
  late final GateRouter<HomeRoute> _homeRouter = GateRouter<HomeRoute>(
    initial: const HomeRoot(),
  );
  late final GateRouter<DiscoverRoute> _discoverRouter =
      GateRouter<DiscoverRoute>(initial: const DiscoverRoot());
  late final GateRouter<ProfileRoute> _profileRouter = GateRouter<ProfileRoute>(
    initial: const ProfileRoot(),
  );
  late final BranchedShellRouter _shell = BranchedShellRouter(
    branches: [_homeRouter, _discoverRouter, _profileRouter],
  );

  @override
  void dispose() {
    _shell.dispose();
    _homeRouter.dispose();
    _discoverRouter.dispose();
    _profileRouter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GateBranchedShell(
      shell: _shell,
      branches: [
        GateBranch<HomeRoute>(
          router: _homeRouter,
          pageBuilder: (context, route) => switch (route) {
            HomeRoot() => const _HomeScreen(),
            ProductDetail(:final id) => _ProductDetailScreen(id: id),
          },
        ),
        GateBranch<DiscoverRoute>(
          router: _discoverRouter,
          pageBuilder: (context, route) => switch (route) {
            DiscoverRoot() => const _DiscoverScreen(),
            FeedItem(:final id) => _FeedItemScreen(id: id),
          },
        ),
        GateBranch<ProfileRoute>(
          router: _profileRouter,
          pageBuilder: (context, route) => switch (route) {
            ProfileRoot() => const _ProfileScreen(),
          },
        ),
      ],
      chromeBuilder: (context, active, branchContent, switchBranch) {
        return Scaffold(
          body: branchContent,
          bottomNavigationBar: NavigationBar(
            selectedIndex: active,
            onDestinationSelected: switchBranch,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(
                icon: Icon(Icons.explore),
                label: 'Discover',
              ),
              NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
            ],
          ),
        );
      },
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: ListView(
        children: [
          for (final id in ['sku-1', 'sku-2', 'sku-42'])
            ListTile(
              title: Text('Product $id'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.router<HomeRoute>().push(ProductDetail(id)),
            ),
        ],
      ),
    );
  }
}

class _DiscoverScreen extends StatelessWidget {
  const _DiscoverScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      body: ListView(
        children: [
          for (final id in ['post-1', 'post-2', 'post-3'])
            ListTile(
              title: Text('Feed item $id'),
              onTap: () => context.router<DiscoverRoute>().push(FeedItem(id)),
            ),
        ],
      ),
    );
  }
}

class _FeedItemScreen extends StatelessWidget {
  const _FeedItemScreen({required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Feed item $id')),
      body: Center(child: Text('Discover-only screen for $id')),
    );
  }
}

class _ProfileScreen extends StatelessWidget {
  const _ProfileScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton(
              // Top-level navigation: push on the MAIN router
              // (context.router<AppRoute>()) so Settings appears OVER
              // the shell. URL becomes /settings.
              onPressed: () =>
                  context.router<AppRoute>().push(const Settings()),
              child: const Text('Settings'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.branchedShell().switchTo(0),
              child: const Text('Go to Home tab'),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: auth.logOut, child: const Text('Log out')),
          ],
        ),
      ),
    );
  }
}

class _ProductDetailScreen extends StatelessWidget {
  const _ProductDetailScreen({required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Product $id')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Detail page for $id',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Add to cart'),
              onPressed: () async {
                // Run a typed modal flow on the MAIN router.
                // Branch routers don't have a delegate to render
                // overlays, so flows always go through the main.
                final qty = await router.run(ConfirmAddToCart(id));
                if (qty != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Added $qty × $id to cart.')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsScreen extends StatelessWidget {
  const _SettingsScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(
        child: Text(
          'Top-level page reached at /settings. Back goes to the shell.',
        ),
      ),
    );
  }
}

// ─── Modal flow screens (still AppRoute — flows are top-level) ───────

class _ConfirmAddToCartScreen extends StatefulWidget {
  const _ConfirmAddToCartScreen({required this.productId});
  final String productId;
  @override
  State<_ConfirmAddToCartScreen> createState() =>
      _ConfirmAddToCartScreenState();
}

class _ConfirmAddToCartScreenState extends State<_ConfirmAddToCartScreen> {
  int _qty = 1;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Add ${widget.productId}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: context.dismissFlow,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('How many?'),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                ),
                Text('$_qty', style: Theme.of(context).textTheme.headlineSmall),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => setState(() => _qty++),
                ),
              ],
            ),
            const Spacer(),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  // context.router<AppRoute>() inside the flow resolves
                  // to the flow's sub-router (not the main router).
                  context.router<AppRoute>().push(
                    ConfirmAddToCartReview(
                      productId: widget.productId,
                      quantity: _qty,
                    ),
                  );
                },
                child: const Text('Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmAddToCartReviewScreen extends StatelessWidget {
  const _ConfirmAddToCartReviewScreen({
    required this.productId,
    required this.quantity,
  });
  final String productId;
  final int quantity;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Adding $quantity × $productId to your cart.'),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => context.router<AppRoute>().pop(),
                  child: const Text('Back'),
                ),
                FilledButton(
                  onPressed: () => context.completeFlow<int>(quantity),
                  child: const Text('Confirm'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
