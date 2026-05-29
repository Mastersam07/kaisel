import 'package:flutter/material.dart';
import 'package:gate/gate.dart';

// ─────────────────────────────────────────────────────────────────────
// 1. Routes — sealed type with default props-based equality (no manual
//    == / hashCode anywhere).
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

/// Marker mixin for routes that require an authenticated user. Used by
/// the auth guard to decide whether to redirect to Login.
mixin RequiresAuth on AppRoute {}

/// The main app shell — bottom-nav with Home/Discover/Profile tabs.
final class MainShell extends AppRoute with RequiresAuth {
  const MainShell();
}

// Routes that can appear in any branch of the shell:
final class HomeRoot extends AppRoute with RequiresAuth {
  const HomeRoot();
}

final class DiscoverRoot extends AppRoute with RequiresAuth {
  const DiscoverRoot();
}

final class ProfileRoot extends AppRoute with RequiresAuth {
  const ProfileRoot();
}

final class ProductDetail extends AppRoute with RequiresAuth {
  const ProductDetail(this.id);
  final String id;

  @override
  List<Object?> get props => [id];
}

final class Settings extends AppRoute with RequiresAuth {
  const Settings();
}

// ─────────────────────────────────────────────────────────────────────
// 2. Auth state — a simple ValueNotifier so the guard can read current
//    state and so screens can react to login/logout.
// ─────────────────────────────────────────────────────────────────────

class AuthState extends ValueNotifier<bool> {
  AuthState() : super(false);
  void logIn() => value = true;
  void logOut() => value = false;
}

final auth = AuthState();

// ─────────────────────────────────────────────────────────────────────
// 3. Guards — pure-function transforms over (current, proposed).
// ─────────────────────────────────────────────────────────────────────

GateGuard<AppRoute> authGuard(AuthState auth) {
  return (current, proposed) {
    final needsAuth = proposed.any((r) => r is RequiresAuth);
    if (needsAuth && !auth.value) {
      return const [Login()];
    }
    return proposed;
  };
}

GateGuard<AppRoute> splashRedirectGuard(AuthState auth) {
  // Once auth state is known (we model it as "any push past splash"),
  // bounce Splash out of the way. Demonstrates a state-based guard that
  // doesn't need to refuse, just nudge the destination.
  return (current, proposed) {
    if (proposed.length == 1 && proposed.single is Splash) {
      return [auth.value ? const MainShell() : const Login()];
    }
    return proposed;
  };
}

// ─────────────────────────────────────────────────────────────────────
// 4. URL codec — opt-in. Comment out the parser registration to run
//    mobile-only without URLs.
// ─────────────────────────────────────────────────────────────────────

class AppCodec implements GateCodec<AppRoute> {
  const AppCodec();

  @override
  Uri encode(AppRoute route) => switch (route) {
        Splash() => Uri(path: '/'),
        Login() => Uri(path: '/login'),
        MainShell() => Uri(path: '/app'),
        HomeRoot() => Uri(path: '/app/home'),
        DiscoverRoot() => Uri(path: '/app/discover'),
        ProfileRoot() => Uri(path: '/app/profile'),
        ProductDetail(:final id) => Uri(path: '/products/$id'),
        Settings() => Uri(path: '/settings'),
        RequiresAuth() => Uri(path: '/login')
      };

  @override
  AppRoute? decode(Uri uri) {
    return switch (uri.pathSegments) {
      [] || [''] => const Splash(),
      ['login'] => const Login(),
      ['app'] => const MainShell(),
      ['app', 'home'] => const HomeRoot(),
      ['app', 'discover'] => const DiscoverRoot(),
      ['app', 'profile'] => const ProfileRoot(),
      ['products', final id] => ProductDetail(id),
      ['settings'] => const Settings(),
      _ => null,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────
// 5. Wire it up.
// ─────────────────────────────────────────────────────────────────────

final router = GateRouter<AppRoute>(
  initial: const Splash(),
  guards: [splashRedirectGuard(auth), authGuard(auth)],
);

void main() {
  // Listen for logout — bounce to login from anywhere.
  auth.addListener(() {
    if (!auth.value) {
      router.set(const [Login()]);
    }
  });

  runApp(
    MaterialApp.router(
      title: 'Gate v0.2 example',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      routerDelegate: GateRouterDelegate<AppRoute>(
        router: router,
        builder: _buildPage,
      ),
      routeInformationParser: GateRouteInformationParser<AppRoute>(
        codec: const AppCodec(),
        fallback: const Splash(),
      ),
    ),
  );
}

// One pattern-matched page builder shared by the root router and every
// branch in the shell. Add a variant → this becomes a compile error.
Widget _buildPage(BuildContext context, AppRoute route) => switch (route) {
      Splash() => const _SplashScreen(),
      Login()=> const _LoginScreen(),
      MainShell() => const _MainShellScreen(),
      HomeRoot() => const _HomeScreen(),
      DiscoverRoot() => const _DiscoverScreen(),
      ProfileRoot() => const _ProfileScreen(),
      ProductDetail(:final id) => _ProductDetailScreen(id: id),
      Settings() => const _SettingsScreen(),
      RequiresAuth() => const _LoginScreen()
    };

// ─────────────────────────────────────────────────────────────────────
// 6. Screens.
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
    // Nudge the splash forward; the guard will redirect to login or
    // main shell depending on auth state.
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
              NavigationDestination(
                  icon: Icon(Icons.person), label: 'Profile'),
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
              onTap: () => context
                  .branchRouter<AppRoute>()
                  .push(ProductDetail(id)),
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
              .branchRouter<AppRoute>()
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
            FilledButton(
              onPressed: () => context
                  .branchRouter<AppRoute>()
                  .push(const Settings()),
              child: const Text('Settings'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                // Logout — the auth listener bounces us to login.
                auth.logOut();
              },
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
            const SizedBox(height: 16),
            TextButton(
              onPressed: () =>
                  context.shellRouter<AppRoute>().switchTo(2),
              child: const Text('Jump to Profile tab'),
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
      body: const Center(child: Text('Nothing to see here.')),
    );
  }
}
