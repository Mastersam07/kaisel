# gate

A Dart 3-native Flutter router built on sealed routes, pattern matching, and a stack-as-state model. **No string paths. No codegen.**

```dart
sealed class AppRoute extends GateRoute {
  const AppRoute();
}

final class Home extends AppRoute { const Home(); }
final class ProductDetail extends AppRoute {
  const ProductDetail(this.id);
  final String id;
}

final router = GateRouter<AppRoute>(initial: const Home());

router.push(const ProductDetail('sku-42'));  // typed args
router.pop();
router.set([const Home(), const ProductDetail('sku-99')]);  // direct surgery
```

## Why

The two dominant Flutter routing libraries — `go_router` and `auto_route` — were architected before Dart 3 and still organize themselves around a string-path primitive (`'/products/:id'`). Type safety is bolted on with `build_runner`. The URL becomes the source of truth for route definitions, even on mobile-only apps that don't use URLs.

Dart 3 has had the type machinery to do better since 2023: sealed classes, exhaustive pattern matching, records. `gate` is what a routing library looks like when you start from those primitives instead of working around their absence.

The architectural posture, in one line: **the route stack is a `List<R>`, navigation is list manipulation, the URL is an optional codec on top.**

## What you get in v0.1

- A typed route stack expressed as `List<R>` where `R` is your sealed class.
- `push` / `pop` / `replace` / `set` / `popUntil` — navigation as list ops.
- A `RouterDelegate` and `RouteInformationParser` that plug into `MaterialApp.router`.
- A `GateCodec` interface for URL ↔ route mapping (opt-in; ignorable on mobile-only).
- Pattern-matched page resolution with compile-time exhaustiveness checking.
- No codegen. No string parameters. No `extra`.
- Pure-Dart unit tests for the navigation state (no widget tree needed).

## Deliberately not in v0.1

To stay coherent and shippable, these are explicit v0.2+ scope:

- Guards as pure-function transforms in a pipeline.
- `Shell` / `Branch` as primitives for tab/bottom-nav with scoped state.
- Modal sub-flows with typed result returns (`await router.run<T>(...)`).
- Composable `RouteModule`s mountable at URL prefixes.
- Multi-route URL encoding (deep stacks like `/a/b/c` decoding to multiple frames).
- Adaptive layout policies on routes (master-detail responsive).
- Direction-aware transitions and shared-element transitions.

Each of these has a clear design in the companion article that motivated the package; they're staged so the v0.1 API can stabilise before they layer on.

## Usage

### 1. Declare your route type

```dart
sealed class AppRoute extends GateRoute {
  const AppRoute();
}

final class Home extends AppRoute { const Home(); }

final class ProductDetail extends AppRoute {
  const ProductDetail(this.id);
  final String id;

  @override
  bool operator ==(Object other) =>
      other is ProductDetail && other.id == id;
  @override
  int get hashCode => id.hashCode;
}
```

`gate` doesn't bake in an equality story — use `Equatable`, `freezed sealed`, or hand-roll, whichever you prefer. The router uses identity-stable internal entries for navigator page keying, so duplicate equal routes on the stack are fine.

### 2. Wire it up

```dart
void main() {
  final router = GateRouter<AppRoute>(initial: const Home());
  runApp(MaterialApp.router(
    routerDelegate: GateRouterDelegate<AppRoute>(
      router: router,
      builder: (context, route) => switch (route) {
        Home() => const HomeScreen(),
        ProductDetail(:final id) => ProductDetailScreen(id: id),
      },
    ),
  ));
}
```

If you add a new variant to `AppRoute` and forget to handle it in the switch, the compiler fails the build. That's the entire point.

### 3. URLs (optional)

If you target web or want deep links, implement a codec:

```dart
class AppCodec implements GateCodec<AppRoute> {
  @override
  Uri encode(AppRoute route) => switch (route) {
    Home() => Uri(path: '/'),
    ProductDetail(:final id) => Uri(path: '/products/$id'),
  };

  @override
  AppRoute? decode(Uri uri) => switch (uri.pathSegments) {
    [] || [''] => const Home(),
    ['products', final id] => ProductDetail(id),
    _ => null,
  };
}
```

Then pass a parser to `MaterialApp.router`:

```dart
routeInformationParser: GateRouteInformationParser<AppRoute>(
  codec: const AppCodec(),
  fallback: const Home(),
),
```

If you don't need URLs, don't implement the codec. The router works fine without it.

## Why no equality story baked in

Routing libraries that bake in an equality solution force a choice — codegen (`freezed`), runtime helper (`Equatable`), or a particular DSL — onto every consumer. `gate` deliberately punts: declare your routes however you like, just make `==` correct. Sealed classes with `const` constructors + manual `==` are perfectly fine for a small surface; `Equatable` is the ergonomic choice for wider state; `freezed sealed` works too. The router doesn't care.

## Status

v0.1 is the foundation. The API will not break for the v0.1.x line. v0.2 layers guards and shells on top of the same core without changing the route/stack model.

## Comparison

For a longer-form motivation, see the companion article: *Flutter Routing Is a Pre-Dart-3 Design.*
