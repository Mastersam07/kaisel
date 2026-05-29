import 'package:flutter/material.dart';
import 'package:gate/gate.dart';

// ─────────────────────────────────────────────────────────────────────
// 1. Routes
// ─────────────────────────────────────────────────────────────────────

sealed class AppRoute extends GateRoute {
  const AppRoute();
}

final class Splash extends AppRoute {
  const Splash();
}

final class Login extends AppRoute {
  const Login();
}

/// Marker interface for routes that require an authenticated user.
///
/// Declared as a standalone interface (rather than `mixin RequiresAuth
/// on AppRoute`) so it lives outside the sealed hierarchy. A mixin
/// declared `on AppRoute` becomes a subtype of `AppRoute` from the
/// exhaustiveness checker's perspective, which then insists on a
/// `RequiresAuth()` pattern in any `switch` over `AppRoute` even when
/// every concrete final class is enumerated. Implementing a standalone
/// interface sidesteps that.
abstract interface class RequiresAuth {}

final class MainShell extends AppRoute implements RequiresAuth {
  const MainShell();
}

// Branch roots:
final class HomeRoot extends AppRoute implements RequiresAuth {
  const HomeRoot();
}

final class DiscoverRoot extends AppRoute implements RequiresAuth {
  const DiscoverRoot();
}

final class ProfileRoot extends AppRoute implements RequiresAuth {
  const ProfileRoot();
}

// In-branch detail page (Home branch).
final class ProductDetail extends AppRoute implements RequiresAuth {
  const ProductDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

// Top-level page reachable from inside the shell.
final class Settings extends AppRoute implements RequiresAuth {
  const Settings();
}

// ─── Modal flow routes ───────────────────────────────────────────────
//
// ConfirmAddToCart implements GateModalRoute<int>: the flow returns
// the chosen quantity, or null if dismissed.

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
// 3. Guards
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
// 4. Multi-route URL codec
//
// A *stack* codec: one URL can decode into multiple frames so the back
// button has somewhere sensible to go on deep links.
// ─────────────────────────────────────────────────────────────────────

class AppStackCodec implements GateStackCodec<AppRoute> {
  const AppStackCodec();

  @override
  Uri encode(List<AppRoute> stack) => switch (stack.last) {
        Splash() => Uri(path: '/'),
        Login() => Uri(path: '/login'),
        MainShell() => Uri(path: '/app'),
        Settings() => Uri(path: '/settings'),
        // Branches & in-branch routes don't have main-router URLs —
        // they live inside the shell's nested navigators.
        HomeRoot() ||
        DiscoverRoot() ||
        ProfileRoot() ||
        ProductDetail() ||
        ConfirmAddToCart() ||
        ConfirmAddToCartReview() =>
          Uri(path: '/app'),
      };

  @override
  List<AppRoute>? decode(Uri uri) {
    return switch (uri.pathSegments) {
      [] || [''] => const [Splash()],
      ['login'] => const [Login()],
      ['app'] => const [MainShell()],
      // /settings restores a deep stack so back goes to the shell.
      ['settings'] => const [MainShell(), Settings()],
      _ => null,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────
// 5. Wire it up
// ─────────────────────────────────────────────────────────────────────

final router = GateRouter<AppRoute>(
  initial: const Splash(),
  guards: [splashRedirectGuard(auth), authGuard(auth)],
);

void main() {
  auth.addListener(() {
    if (!auth.value) {
      router.set(const [Login()]);
    }
  });

  runApp(
    MaterialApp.router(
      title: 'Gate v0.3 example',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      routerDelegate: GateRouterDelegate<AppRoute>(
        router: router,
        builder: _buildPage,
        modalBuilder: _buildModal,
      ),
      routeInformationParser: GateRouteInformationParser<AppRoute>(
        codec: const AppStackCodec(),
        fallback: const [Splash()],
      ),
    ),
  );
}

Widget _buildPage(BuildContext context, AppRoute route) => switch (route) {
      Splash() => const _SplashScreen(),
      Login() => const _LoginScreen(),
      MainShell() => const _MainShellScreen(),
      HomeRoot() => const _HomeScreen(),
      DiscoverRoot() => const _DiscoverScreen(),
      ProfileRoot() => const _ProfileScreen(),
      ProductDetail(:final id) => _ProductDetailScreen(id: id),
      Settings() => const _SettingsScreen(),
      ConfirmAddToCart(:final productId) =>
        _ConfirmAddToCartScreen(productId: productId),
      ConfirmAddToCartReview(:final productId, :final quantity) =>
        _ConfirmAddToCartReviewScreen(
          productId: productId,
          quantity: quantity,
        ),
    };

/// Renders an active modal flow over the main UI as a centered card on
/// a dimmed backdrop.
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

class _MainShellScreen extends StatelessWidget {
  const _MainShellScreen();
  @override
  Widget build(BuildContext context) {
    return GateShell<AppRoute>(
      branchInitials: const [HomeRoot(), DiscoverRoot(), ProfileRoot()],
      pageBuilder: _buildPage,
      chromeBuilder: (context, active, branchContent, switchBranch) {
        return Scaffold(
          body: branchContent,
          bottomNavigationBar: NavigationBar(
            selectedIndex: active,
            onDestinationSelected: switchBranch,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(
                  icon: Icon(Icons.explore), label: 'Discover'),
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
              onTap: () => context.router<AppRoute>().push(ProductDetail(id)),
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
      body: Center(
        child: FilledButton(
          onPressed: () => context
              .router<AppRoute>()
              .push(const ProductDetail('discovery-pick')),
          child: const Text('Featured product'),
        ),
      ),
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
            // Settings is a top-level route — push it on the main
            // router so it appears OVER the shell.
            FilledButton(
              onPressed: () => router.push(const Settings()),
              child: const Text('Settings'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: auth.logOut,
              child: const Text('Log out'),
            ),
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
            Text('Detail page for $id',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Add to cart'),
              onPressed: () async {
                // Run a typed modal flow. The result type (int?) is
                // inferred from ConfirmAddToCart's GateModalRoute<int>.
                // We call run() on the main router — modals overlay
                // everything, including the shell chrome.
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
        child: Text('Top-level page reached at /settings. Back goes home.'),
      ),
    );
  }
}

// ─── Modal flow screens ──────────────────────────────────────────────

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
          // dismissFlow resolves the awaiter with null.
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
                  // context.router resolves to the FLOW's sub-router
                  // because the flow screen sits inside RouterScope
                  // installed by the delegate.
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
                  onPressed: () =>
                      // Resolve the awaiter with the chosen quantity.
                      context.completeFlow<int>(quantity),
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
