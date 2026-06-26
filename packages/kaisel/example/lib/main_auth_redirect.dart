// Redirect to login, then continue to the intended destination.
//
// Tapping "Pay" on the Cart navigates to a protected route. While logged out, an
// auth guard rewrites that navigation to Login and remembers the intended stack;
// logging in replays it with `router.set`, so you land on Payment with Cart
// still beneath it (Android back goes Payment -> Cart -> Home). A deep link to a
// protected route would flow through the same guard, so deep-link-after-auth
// needs no extra code.
//
//   flutter run -t lib/main_auth_redirect.dart
import 'package:flutter/material.dart';
import 'package:kaisel/kaisel.dart';

/// Marker for routes that require authentication.
abstract interface class RequiresAuth {}

sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

final class Home extends AppRoute {
  const Home();
}

final class Cart extends AppRoute {
  const Cart();
}

final class Login extends AppRoute {
  const Login();
}

final class Payment extends AppRoute implements RequiresAuth {
  const Payment();
}

final class Receipt extends AppRoute implements RequiresAuth {
  const Receipt();
}

class Auth extends ChangeNotifier {
  bool loggedIn = false;
  List<AppRoute>? pending; // where the user was headed before the redirect

  void logIn() {
    loggedIn = true;
    notifyListeners();
  }

  void logOut() {
    loggedIn = false;
    notifyListeners();
  }
}

final auth = Auth();

// Runs on every navigation. If the proposed stack reaches a protected route
// while logged out, stash the whole stack and redirect to Login.
List<AppRoute> authGuard(List<AppRoute> current, List<AppRoute> proposed) {
  final needsAuth = proposed.any((r) => r is RequiresAuth);
  if (needsAuth && !auth.loggedIn) {
    auth.pending = proposed;
    return [...proposed.where((r) => r is! RequiresAuth), const Login()];
  }
  return proposed;
}

final _config = KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  guards: [authGuard],
  builder: (context, route) => switch (route) {
    Home() => const _HomeScreen(),
    Cart() => const _CartScreen(),
    Login() => const _LoginScreen(),
    Payment() => const _PaymentScreen(),
    Receipt() => const _ReceiptScreen(),
  },
);

void main() => runApp(MaterialApp.router(routerConfig: _config));

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();

  @override
  Widget build(BuildContext context) => _Screen(
    title: 'Home',
    child: FilledButton(
      onPressed: () => context.push(const Cart()),
      child: const Text('Go to cart'),
    ),
  );
}

class _CartScreen extends StatelessWidget {
  const _CartScreen();

  @override
  Widget build(BuildContext context) => _Screen(
    title: 'Cart',
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('1 item — \$42'),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => context.push(const Payment()),
          child: const Text('Pay'),
        ),
      ],
    ),
  );
}

class _LoginScreen extends StatelessWidget {
  const _LoginScreen();

  @override
  Widget build(BuildContext context) {
    final headed = auth.pending?.last;
    return _Screen(
      title: 'Login',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            headed == null
                ? 'Please log in.'
                : 'Log in to continue to ${headed.runtimeType}.',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              auth.logIn();
              final dest = auth.pending ?? const [Home()];
              auth.pending = null;
              context.router<AppRoute>().set(dest); // guard now passes
            },
            child: const Text('Log in'),
          ),
        ],
      ),
    );
  }
}

class _PaymentScreen extends StatelessWidget {
  const _PaymentScreen();

  @override
  Widget build(BuildContext context) => _Screen(
    title: 'Payment',
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Confirm payment of \$42'),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => context.push(const Receipt()),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
}

class _ReceiptScreen extends StatelessWidget {
  const _ReceiptScreen();

  @override
  Widget build(BuildContext context) =>
      const _Screen(title: 'Receipt', child: Text('Paid. Thank you!'));
}

// Chrome with a sign-in/out indicator, so the guard's effect is visible.
class _Screen extends StatelessWidget {
  const _Screen({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            Center(child: Text(auth.loggedIn ? 'signed in' : 'signed out')),
            if (auth.loggedIn)
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () {
                  auth.logOut();
                  context.router<AppRoute>().set(const [Home()]);
                },
              ),
            const SizedBox(width: 12),
          ],
        ),
        body: Center(child: child),
      ),
    );
  }
}
