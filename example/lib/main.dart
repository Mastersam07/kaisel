import 'package:flutter/material.dart';
import 'package:gate/gate.dart';

// 1. Declare the route type as a sealed class.
//    Variants are typed; their fields are real fields, not strings.
sealed class AppRoute extends GateRoute {
  const AppRoute();
}

final class Home extends AppRoute {
  const Home();
  @override
  bool operator ==(Object other) => other is Home;
  @override
  int get hashCode => 0;
}

final class ProductList extends AppRoute {
  const ProductList({this.category});
  final String? category;

  @override
  bool operator ==(Object other) =>
      other is ProductList && other.category == category;
  @override
  int get hashCode => category.hashCode;
}

final class ProductDetail extends AppRoute {
  const ProductDetail(this.id);
  final String id;

  @override
  bool operator ==(Object other) =>
      other is ProductDetail && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

final class Cart extends AppRoute {
  const Cart();
  @override
  bool operator ==(Object other) => other is Cart;
  @override
  int get hashCode => 2;
}

// 2. A codec — only needed if you want URLs (web, deep links).
//    Plain mobile apps can skip this and not register a parser.
class AppCodec implements GateCodec<AppRoute> {
  const AppCodec();

  @override
  Uri encode(AppRoute route) => switch (route) {
        Home() => Uri(path: '/'),
        ProductList(:final category) => Uri(
            path: '/products',
            queryParameters: {
              'category': ?category,
            },
          ),
        ProductDetail(:final id) => Uri(path: '/products/$id'),
        Cart() => Uri(path: '/cart'),
      };

  @override
  AppRoute? decode(Uri uri) {
    final segments = uri.pathSegments;
    return switch (segments) {
      [] || [''] => const Home(),
      ['products'] => ProductList(category: uri.queryParameters['category']),
      ['products', final id] => ProductDetail(id),
      ['cart'] => const Cart(),
      _ => null,
    };
  }
}

// 3. Wire it up.
void main() {
  final router = GateRouter<AppRoute>(initial: const Home());

  runApp(
    MaterialApp.router(
      title: 'Gate example',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      routerDelegate: GateRouterDelegate<AppRoute>(
        router: router,
        // 4. Pattern-matched page resolution. The compiler enforces
        //    exhaustiveness over AppRoute — add a variant and this
        //    switch becomes a compile error.
        builder: (context, route) => switch (route) {
          Home() => HomeScreen(router: router),
          ProductList(:final category) =>
            ProductListScreen(router: router, category: category),
          ProductDetail(:final id) =>
            ProductDetailScreen(router: router, id: id),
          Cart() => CartScreen(router: router),
        },
      ),
      routeInformationParser: GateRouteInformationParser<AppRoute>(
        codec: const AppCodec(),
        fallback: const Home(),
      ),
    ),
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.router});
  final GateRouter<AppRoute> router;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton(
              onPressed: () => router.push(const ProductList()),
              child: const Text('Browse all products'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () =>
                  router.push(const ProductList(category: 'shoes')),
              child: const Text('Browse shoes'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => router.set(const [
                Home(),
                ProductList(category: 'shoes'),
                ProductDetail('sku-42'),
              ]),
              child: const Text('Jump directly into a deep stack'),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductListScreen extends StatelessWidget {
  const ProductListScreen({
    super.key,
    required this.router,
    required this.category,
  });
  final GateRouter<AppRoute> router;
  final String? category;

  @override
  Widget build(BuildContext context) {
    final title = category == null ? 'All products' : 'Products: $category';
    final ids = ['sku-1', 'sku-2', 'sku-42', 'sku-99'];
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        children: [
          for (final id in ids)
            ListTile(
              title: Text('Product $id'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => router.push(ProductDetail(id)),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => router.push(const Cart()),
        child: const Icon(Icons.shopping_cart),
      ),
    );
  }
}

class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({
    super.key,
    required this.router,
    required this.id,
  });
  final GateRouter<AppRoute> router;
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
            FilledButton(
              onPressed: () => router.push(const Cart()),
              child: const Text('Add to cart and view cart'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  router.popUntil((r) => r is Home),
              child: const Text('Back to home (popUntil)'),
            ),
          ],
        ),
      ),
    );
  }
}

class CartScreen extends StatelessWidget {
  const CartScreen({super.key, required this.router});
  final GateRouter<AppRoute> router;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Your cart is full of imaginary things.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => router.set(const [Home()]),
              child: const Text('Checkout (reset stack to home)'),
            ),
          ],
        ),
      ),
    );
  }
}
