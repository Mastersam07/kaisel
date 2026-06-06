// Route-pair transitions demo for the kaisel router.
//
// Run from the `example/` directory:
//
//   flutter run -t lib/main_transitions.dart
//
// What this shows
// ---------------
// Customising page transitions via `pageWrapper`. The wrapper
// receives a `KaiselPageWrapperContext<R>` and pattern-matches on the
// route (and optionally the route below it) to pick a `Page`
// subclass with a custom transition.
//
// Three transitions on display:
//
// 1. **Settings** slides up from the bottom regardless of where it
//    was opened from. Destination-only matching: `(_, Settings())`.
//
// 2. **About** fades in. Destination-only matching: `(_, About())`.
//
// 3. **Product → Product** (when a product detail pushes another
//    product, e.g., via a "Related Product" link) cross-fades. This
//    is the route-pair case: `(Product(), Product())`. Pushing a
//    Product on top of a Product gives the new page's `ctx.previous`
//    as the old Product, which is what the pair-match keys on.
//
// Note that the Navigator still drives push/pop *direction*
// (forward on add, reverse on remove). The wrapper only picks the
// transition *style* (which `Page` subclass to construct).

import 'package:flutter/material.dart';
import 'package:kaisel/kaisel.dart';

sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

final class Home extends AppRoute {
  const Home();
}

final class Product extends AppRoute {
  const Product(this.id);
  final int id;
  @override
  List<Object?> get props => [id];
}

final class Settings extends AppRoute {
  const Settings();
}

final class About extends AppRoute {
  const About();
}

/// Slides in from the bottom and slides back down on pop. Used for
/// the Settings route to give it a modal-from-bottom feel.
class _SlideUpPage extends Page<Object?> {
  const _SlideUpPage({required LocalKey super.key, required this.child});

  final Widget child;

  @override
  Route<Object?> createRoute(BuildContext context) {
    return PageRouteBuilder<Object?>(
      settings: this,
      pageBuilder: (_, _, _) => child,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      transitionsBuilder: (_, anim, _, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
    );
  }
}

/// Fades in. Used for About (informational, not navigational) and
/// for Product → Product (cross-fade between related items).
class _FadePage extends Page<Object?> {
  const _FadePage({required LocalKey super.key, required this.child});

  final Widget child;

  @override
  Route<Object?> createRoute(BuildContext context) {
    return PageRouteBuilder<Object?>(
      settings: this,
      pageBuilder: (_, _, _) => child,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (_, anim, _, child) {
        return FadeTransition(opacity: anim, child: child);
      },
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();

  @override
  Widget build(BuildContext context) {
    final router = context.router<AppRoute>();
    return Scaffold(
      appBar: AppBar(title: const Text('Transitions demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ActionTile(
            icon: Icons.shopping_bag_outlined,
            title: 'Open a product',
            subtitle: 'Material-style forward slide (default)',
            onTap: () => router.push(const Product(1)),
          ),
          const SizedBox(height: 8),
          _ActionTile(
            icon: Icons.settings_outlined,
            title: 'Open Settings',
            subtitle: 'Slide up from the bottom',
            onTap: () => router.push(const Settings()),
          ),
          const SizedBox(height: 8),
          _ActionTile(
            icon: Icons.info_outline,
            title: 'Open About',
            subtitle: 'Fade in',
            onTap: () => router.push(const About()),
          ),
        ],
      ),
    );
  }
}

class _ProductScreen extends StatelessWidget {
  const _ProductScreen({required this.id});

  final int id;

  @override
  Widget build(BuildContext context) {
    final router = context.router<AppRoute>();
    final nextId = id < 5 ? id + 1 : 1;
    return Scaffold(
      appBar: AppBar(title: Text('Product #$id')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Product #$id',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'A placeholder product. The "Related product" button '
              'below pushes another Product onto the stack. Because '
              'the new page\'s previous is also a Product, the '
              'wrapper picks the fade transition (not the default '
              'Material slide).',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const Spacer(),
            FilledButton.icon(
              icon: const Icon(Icons.arrow_forward),
              label: Text('Related product (#$nextId)'),
              onPressed: () => router.push(Product(nextId)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open Settings from here'),
              onPressed: () => router.push(const Settings()),
            ),
            const SizedBox(height: 24),
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
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.tune),
            title: Text('Preferences'),
            subtitle: Text('Placeholder'),
          ),
          ListTile(
            leading: Icon(Icons.security_outlined),
            title: Text('Privacy'),
            subtitle: Text('Placeholder'),
          ),
          ListTile(
            leading: Icon(Icons.notifications_outlined),
            title: Text('Notifications'),
            subtitle: Text('Placeholder'),
          ),
        ],
      ),
    );
  }
}

class _AboutScreen extends StatelessWidget {
  const _AboutScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'kaisel',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              'A typed routing library for Flutter built around '
              'sealed routes, value equality, and declarative '
              'navigation.',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

final _config = KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  builder: (context, route) => switch (route) {
    Home() => const _HomeScreen(),
    Product(:final id) => _ProductScreen(id: id),
    Settings() => const _SettingsScreen(),
    About() => const _AboutScreen(),
  },
  pageWrapper: _pageWrapper,
);

// The wrapper. Pattern-matches on `(ctx.previous, ctx.route)` to
// pick a Page subclass per route pair. The Navigator handles the
// push/pop direction; the wrapper picks the transition style.
Page<Object?> _pageWrapper(KaiselPageWrapperContext<AppRoute> ctx) {
  return switch ((ctx.previous, ctx.route)) {
    // Settings always slides up, regardless of where it was opened
    // from. Destination-only matching.
    (_, Settings()) => _SlideUpPage(key: ctx.key, child: ctx.child),

    // About always fades in. Destination-only matching.
    (_, About()) => _FadePage(key: ctx.key, child: ctx.child),

    // Product pushing onto Product (e.g., a "Related product"
    // link) cross-fades. Route-pair matching: the new page's
    // `previous` is also a Product.
    (Product(), Product()) => _FadePage(key: ctx.key, child: ctx.child),

    // Everything else: default Material slide.
    _ => MaterialPage<Object?>(key: ctx.key, child: ctx.child),
  };
}

void main() {
  runApp(
    MaterialApp.router(
      title: 'kaisel transitions demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00D4FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        cardColor: const Color(0xFF14141C),
        useMaterial3: true,
      ),
      routerConfig: _config,
    ),
  );
}
