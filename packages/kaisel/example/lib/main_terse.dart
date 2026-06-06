// Ergonomics prototype: the same app, written with the new convenience layer.
//
// BEFORE — the plumbing people call "low-level like Navigator 2.0":
//
//   class _App extends StatefulWidget { ... }
//   class _AppState extends State<_App> {
//     late final KaiselRouter<AppRoute> _router;
//     late final KaiselRouterDelegate<AppRoute> _delegate;
//     @override void initState() {
//       super.initState();
//       _router = KaiselRouter<AppRoute>(initial: const Home());
//       _delegate = KaiselRouterDelegate<AppRoute>(router: _router, builder: …);
//     }
//     @override void dispose() { _delegate.dispose(); _router.dispose(); super.dispose(); }
//     @override Widget build(_) => MaterialApp.router(
//       routerDelegate: _delegate,
//       routeInformationParser: _NoopParser(_router),   // hand-rolled
//     );
//   }
//
//   // call sites:
//   context.router<AppRoute>().push(const ProductDetail('42'));
//   context.router<AppRoute>().pop();
//
// AFTER — below. Top-level config, no StatefulWidget, no parser, terse calls.

import 'package:flutter/material.dart';
import 'package:kaisel/kaisel.dart';

sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

final class Home extends AppRoute {
  const Home();
}

final class ProductDetail extends AppRoute {
  const ProductDetail(this.id);
  final String id;

  @override
  List<Object?> get props => [id];
}

// One value. No StatefulWidget, no manual delegate/parser, no dispose.
final _config = KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  builder: (context, route) => switch (route) {
    Home() => const _HomeScreen(),
    ProductDetail(:final id) => _DetailScreen(id: id),
  },
);

void main() {
  runApp(
    MaterialApp.router(
      // You keep your own MaterialApp — theme, title, everything.
      title: 'kaisel — terse',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      routerConfig: _config,
    ),
  );
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: ElevatedButton(
          // Terse convenience (runtime family check). The idiomatic default
          // is the typed context.router<AppRoute>().push(const ProductDetail(...)).
          onPressed: () => context.push(const ProductDetail('sku-42')),
          child: const Text('Open product'),
        ),
      ),
    );
  }
}

class _DetailScreen extends StatelessWidget {
  const _DetailScreen({required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Product $id')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => context.pop(),
          child: const Text('Back'),
        ),
      ),
    );
  }
}
