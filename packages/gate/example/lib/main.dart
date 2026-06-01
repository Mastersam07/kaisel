import 'package:flutter/material.dart';
import 'package:gate/gate.dart';

// 1. Routes
//
// In v0.4, each shell branch has its own sealed type. AppRoute contains
// only top-level concerns; HomeRoute / DiscoverRoute / ProfileRoute are
// separate hierarchies. The compiler enforces "you can't push a
// DiscoverRoute into the Home tab."

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

// v0.6: a top-level marker route that mounts the Checkout module.
// The module owns its internal routes (CheckoutCart, CheckoutShipping,
// CheckoutConfirm) under its own sealed type. See CheckoutRoute below.
final class CheckoutMount extends AppRoute implements RequiresAuth {
  const CheckoutMount();
}

// Modal flow routes: still AppRoute, because flows run on the main
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

// The Checkout module: a self-contained routing unit.
//
// In v0.6, a RouteModule packages a sealed subtype, an initial stack,
// a page builder, optional guards, and an optional page wrapper. The
// module is `const`-instantiable and would normally ship from a
// separate package (e.g. a payments SDK) without the host knowing
// about its internal routes.

sealed class CheckoutRoute extends GateRoute {
  const CheckoutRoute();
}

final class CheckoutCart extends CheckoutRoute {
  const CheckoutCart();
}

final class CheckoutShipping extends CheckoutRoute {
  const CheckoutShipping();
}

final class CheckoutConfirm extends CheckoutRoute {
  const CheckoutConfirm();
}

class CheckoutModule extends RouteModule<CheckoutRoute> {
  const CheckoutModule();

  @override
  List<CheckoutRoute> get initialStack => const [CheckoutCart()];

  @override
  Widget buildPage(BuildContext context, CheckoutRoute route) =>
      switch (route) {
        CheckoutCart() => const _CheckoutCartScreen(),
        CheckoutShipping() => const _CheckoutShippingScreen(),
        CheckoutConfirm() => const _CheckoutConfirmScreen(),
      };

  // v0.7: the module owns its own URL structure, relative to whatever
  // prefix the host mounts it at. The host's main codec stays
  // checkout-agnostic; ConfigCodecWithModules wires the prefix.
  @override
  ModuleStackCodec<CheckoutRoute>? get codec => const _CheckoutModuleCodec();
}

class _CheckoutModuleCodec extends ModuleStackCodec<CheckoutRoute> {
  const _CheckoutModuleCodec();

  @override
  List<String> encode(List<CheckoutRoute> stack) => switch (stack.last) {
    CheckoutCart() => const [],
    CheckoutShipping() => const ['shipping'],
    CheckoutConfirm() => const ['confirm'],
  };

  // A deep link to .../confirm restores the full [Cart, Shipping,
  // Confirm] stack so back unwinds through the flow rather than
  // popping straight out of the module.
  @override
  List<CheckoutRoute>? decode(List<String> segments) => switch (segments) {
    [] => const [CheckoutCart()],
    ['shipping'] => const [CheckoutCart(), CheckoutShipping()],
    ['confirm'] => const [
      CheckoutCart(),
      CheckoutShipping(),
      CheckoutConfirm(),
    ],
    _ => null,
  };
}

// 2. Auth state

class AuthState extends ValueNotifier<bool> {
  AuthState() : super(false);
  void logIn() => value = true;
  void logOut() => value = false;
}

final auth = AuthState();

// 3. Guards (main router only; once you're past MainShell the user is
//    authenticated for the rest of the session, so branch routers
//    don't need their own auth guards in this example).

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

// 4. URL codec: v0.5 GateConfigCodec, with shell URLs.
//
// v0.5's configuration carries both the main stack and (when a shell
// is mounted) the active branch's stack. We encode each branch into a
// distinct URL prefix so deep links can reach into the shell:
//
//   /                    → Splash
//   /login               → Login
//   /home                → MainShell, Home tab at root
//   /home/products/x     → MainShell, Home tab with ProductDetail(x)
//   /discover            → MainShell, Discover tab at root
//   /discover/items/y    → MainShell, Discover tab with FeedItem(y)
//   /profile             → MainShell, Profile tab
//   /settings            → MainShell, Settings on top

// The host's MAIN-stack codec. After v0.7 it doesn't know anything
// about the Checkout module's URL structure. That ships with the
// module. The composer below wires them together.
class _MainAppCodec implements GateConfigCodec<AppRoute> {
  const _MainAppCodec();

  static const _branchPrefixes = ['home', 'discover', 'profile'];

  @override
  Uri encode(GateConfig<AppRoute> config) {
    // Modal flow routes overlay the app; they don't take URLs of
    // their own. Encode the underlying state instead.
    final top = config.mainStack.last;
    if (top is ConfirmAddToCart || top is ConfirmAddToCartReview) {
      final base = config.mainStack
          .where((r) => r is! ConfirmAddToCart && r is! ConfirmAddToCartReview)
          .toList();
      return encode(
        GateConfig(
          mainStack: base.isEmpty ? const [Splash()] : base,
          nestedState: config.nestedState,
        ),
      );
    }
    // CheckoutMount is intentionally absent from this switch. The
    // composer ([ConfigCodecWithModules]) handles any URL whose top
    // route is a registered module mount, BEFORE delegating to this
    // base codec. By the time we get here, the top is non-module.
    return switch ((top, config.nestedState)) {
      (Splash(), _) => Uri(path: '/'),
      (Login(), _) => Uri(path: '/login'),
      (Settings(), _) => Uri(path: '/settings'),
      (MainShell(), final GateShellConfig shell) => _encodeShell(shell),
      (MainShell(), _) => Uri(path: '/home'),
      (ConfirmAddToCart() || ConfirmAddToCartReview(), _) => Uri(path: '/'),
      // CheckoutMount can't reach here in normal flow; the composer
      // catches it first. The fall-through is for defensive
      // exhaustiveness.
      (CheckoutMount(), _) => Uri(path: '/'),
    };
  }

  Uri _encodeShell(GateShellConfig shell) {
    final prefix = _branchPrefixes[shell.activeBranch];
    final stack = shell.activeBranchStack;
    if (stack.length == 1) return Uri(path: '/$prefix');
    return switch (shell.activeBranch) {
      0 => switch (stack) {
        [HomeRoot(), ProductDetail(:final id)] => Uri(
          path: '/home/products/$id',
        ),
        _ => Uri(path: '/home'),
      },
      1 => switch (stack) {
        [DiscoverRoot(), FeedItem(:final id)] => Uri(
          path: '/discover/items/$id',
        ),
        _ => Uri(path: '/discover'),
      },
      2 => Uri(path: '/profile'),
      _ => Uri(path: '/home'),
    };
  }

  @override
  GateConfig<AppRoute>? decode(Uri uri) {
    // The composer has already attempted module mounts before
    // delegating here, so /checkout/* URLs never reach this method.
    return switch (uri.pathSegments) {
      [] || [''] => GateConfig(mainStack: const [Splash()]),
      ['login'] => GateConfig(mainStack: const [Login()]),
      ['settings'] => GateConfig(mainStack: const [MainShell(), Settings()]),
      ['home'] => _shellAt(0, const [HomeRoot()]),
      ['home', 'products', final id] => _shellAt(0, [
        const HomeRoot(),
        ProductDetail(id),
      ]),
      ['discover'] => _shellAt(1, const [DiscoverRoot()]),
      ['discover', 'items', final id] => _shellAt(1, [
        const DiscoverRoot(),
        FeedItem(id),
      ]),
      ['profile'] => _shellAt(2, const [ProfileRoot()]),
      _ => null,
    };
  }

  GateConfig<AppRoute> _shellAt(int branch, List<GateRoute> stack) =>
      GateConfig(
        mainStack: const [MainShell()],
        nestedState: GateShellConfig(
          activeBranch: branch,
          activeBranchStack: stack,
        ),
      );
}

// v0.7: the composer. Takes a base codec for main-stack routes plus a
// list of module mounts. URLs under a mount's prefix go through the
// module's own codec; everything else falls through to the base.
//
// Each module's URL structure lives inside the module. _MainAppCodec
// is checkout-agnostic. Adding more modules means appending to
// [modules], not editing the main codec.
const appCodec = ConfigCodecWithModules<AppRoute>(
  baseCodec: _MainAppCodec(),
  modules: [
    ModuleMount(
      mountRoute: CheckoutMount(),
      prefix: '/checkout',
      codec: _CheckoutModuleCodec(),
    ),
  ],
);

// 5. Wire it up.
//
// The main router is global. Branch routers are created in
// _MainShellScreen's State so they're tied to the shell's lifecycle.

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
        codec: appCodec,
        fallback: const [Splash()],
      ),
    ),
  );
}

// Main router's pageBuilder: exhaustive over AppRoute (top-level
// routes + modal flow routes). It does NOT handle HomeRoute /
// DiscoverRoute / ProfileRoute. Those are each branch's concern.
Widget _buildMainPage(BuildContext context, AppRoute route) => switch (route) {
  Splash() => const _SplashScreen(),
  Login() => const _LoginScreen(),
  MainShell() => const _MainShellScreen(),
  Settings() => const _SettingsScreen(),
  CheckoutMount() => const GateModuleMount<CheckoutRoute>(
    module: CheckoutModule(),
  ),
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

// 6. Screens

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
      router.replaceTop(const Splash());
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
            FilledButton.tonal(
              // v0.6: pushing CheckoutMount on the main stack mounts
              // the Checkout module. URL becomes /checkout.
              onPressed: () =>
                  context.router<AppRoute>().push(const CheckoutMount()),
              child: const Text('Start checkout'),
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

// Modal flow screens (still AppRoute; flows are top-level)

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

// Checkout module screens (typed to CheckoutRoute)
//
// These screens live inside the Checkout module's typed router.
// `context.router<CheckoutRoute>()` resolves to the module's router;
// `context.router<AppRoute>()` resolves to the host's main router.
// same lookup-by-exact-type semantics as branched shells.

class _CheckoutCartScreen extends StatelessWidget {
  const _CheckoutCartScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('1 item in your cart'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.router<CheckoutRoute>().push(
                const CheckoutShipping(),
              ),
              child: const Text('Continue to shipping'),
            ),
            const SizedBox(height: 12),
            TextButton(
              // Exit the module entirely. Pops CheckoutMount off the
              // main stack.
              onPressed: () => context.router<AppRoute>().pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckoutShippingScreen extends StatelessWidget {
  const _CheckoutShippingScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shipping')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Standard shipping selected'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () =>
                  context.router<CheckoutRoute>().push(const CheckoutConfirm()),
              child: const Text('Review order'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckoutConfirmScreen extends StatelessWidget {
  const _CheckoutConfirmScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Place order?'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                // Complete: pop the whole module off the main stack
                // and surface a confirmation. In a real SDK the
                // module would expose a completion callback or
                // return a Future to the host.
                context.router<AppRoute>().pop();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Order placed.')));
              },
              child: const Text('Place order'),
            ),
          ],
        ),
      ),
    );
  }
}
