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

  @override
  List<Object?> get props => [id];  // value equality for free
}

final router = GateRouter<AppRoute>(initial: const Home());

await router.push(const ProductDetail('sku-42'));
await router.pop();
await router.set([const Home(), const ProductDetail('sku-99')]);
```

## Why

The two dominant Flutter routing libraries — `go_router` and `auto_route` — were architected before Dart 3 and still organize themselves around a string-path primitive (`'/products/:id'`). Type safety is bolted on with `build_runner`. The URL becomes the source of truth for route definitions, even on mobile-only apps that don't use URLs.

Dart 3 has had the type machinery to do better since 2023: sealed classes, exhaustive pattern matching, records. `gate` is what a routing library looks like when you start from those primitives instead of working around their absence.

The architectural posture, in one line: **the route stack is a `List<R>`, navigation is list manipulation, the URL is an optional codec on top, and guards are pure functions in a pipeline.**

## What you get in v0.2

- **Typed route stack** as `List<R>` over your sealed class. Push/pop/replace/set/popUntil are list ops.
- **Default value equality** via `props`. No manual `==`/`hashCode`. No codegen.
- **Guard pipeline** — `FutureOr<List<R>> Function(current, proposed)`. Composable, async-aware, pure-Dart testable.
- **Shells** — `GateShell<R>` for tab/bottom-nav with per-branch back stacks, scoped state, and proper back-button handling.
- **Pattern-matched page resolution** with compile-time exhaustiveness checking.
- **URL routing as an opt-in codec** — `GateCodec<R>` if you want web/deep links, ignorable on mobile-only.
- **Identity-preserving stack diff** — pushing one route doesn't rebuild others.
- **Pure-Dart unit tests** for navigation state (no widget tree needed).

## Deliberately not in v0.2

Coming in v0.3:

- Modal sub-flows with typed result returns (`await router.run<T>(SomeFlow())`).
- Composable `RouteModule`s mountable at URL prefixes.
- Multi-route URL encoding (deep stacks decoding to multiple frames).
- Adaptive layout policies on routes (master-detail responsive).
- Direction-aware and shared-element transitions.
- Per-branch typed route subtypes inside a shell.

Each has a clear design in the companion article that motivated the package; they're staged so the foundational API can stabilise before they layer on.

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
  List<Object?> get props => [id];
}
```

No-field variants get equality automatically (`Home() == Home()`). Variants with fields override `props`. If you need different equality semantics, override `==` and `hashCode` directly — your override wins.

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

Add a variant and the switch fails to compile until you handle it. That's the entire point.

### 3. Guards

Guards are `FutureOr<List<R>> Function(current, proposed)`. They run in order, each receiving the previous's output:

```dart
GateGuard<AppRoute> authGuard(ValueListenable<bool> loggedIn) {
  return (current, proposed) {
    final needsAuth = proposed.any((r) => r is RequiresAuth);
    if (needsAuth && !loggedIn.value) return const [Login()];
    return proposed;
  };
}

final router = GateRouter<AppRoute>(
  initial: const Home(),
  guards: [authGuard(authNotifier)],
);
```

Sync or async — async guards make the navigation async, sync ones complete synchronously. Each guard either allows (return proposed), redirects (return something different), or refuses (return current).

Guards do **not** run on system back. The pop has already animated by the time we hear about it; running guards there would cause visible jumps. State-driven redirects (e.g. force back to login on logout) should be listeners on app state that call `router.set` directly.

### 4. Shells (bottom-nav with per-tab state)

```dart
builder: (context, route) => switch (route) {
  MainShell() => GateShell<AppRoute>(
    branchInitials: const [HomeRoot(), DiscoverRoot(), ProfileRoot()],
    pageBuilder: (context, route) => switch (route) {
      HomeRoot() => const HomeScreen(),
      DiscoverRoot() => const DiscoverScreen(),
      ProfileRoot() => const ProfileScreen(),
      ProductDetail(:final id) => ProductDetailScreen(id: id),
      // ...any variant reachable from any branch...
    },
    chromeBuilder: (context, active, branchContent, switchBranch) => Scaffold(
      body: branchContent,
      bottomNavigationBar: NavigationBar(
        selectedIndex: active,
        onDestinationSelected: switchBranch,
        destinations: const [/* ... */],
      ),
    ),
    branchScope: (context, index, child) => MyBlocProvider(
      branch: index,
      child: child,
    ),
  ),
  Login() => const LoginScreen(),
},
```

Inside any branch screen:

```dart
context.branchRouter<AppRoute>().push(const ProductDetail('42')); // push within tab
context.shellRouter<AppRoute>().switchTo(2);                       // change tab
```

Each branch keeps its own back stack (via `IndexedStack`), and Android back unwinds the active branch first; only at branch root does back fall through to the parent router.

### 5. URLs (optional)

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

Pass a parser to `MaterialApp.router`:

```dart
routeInformationParser: GateRouteInformationParser<AppRoute>(
  codec: const AppCodec(),
  fallback: const Home(),
),
```

If you don't need URLs, don't implement the codec.

## Why no equality codegen

Routing libraries that bake in `freezed` force codegen on every consumer. `gate` provides default `props`-based equality on `GateRoute` itself, so the common case is a one-line override. If you want `freezed sealed`, that still works — your override wins. If you want Equatable, declare your routes with `extends GateRoute with EquatableMixin`. The library doesn't impose a choice.

## Status

v0.2 is the production-shaped surface — routes, guards, shells, URLs. Public API will be stable for the v0.2.x line. v0.3 layers modal flows and route modules on top of this same core.

## Comparison

For a longer-form motivation, see the companion article: *Flutter Routing Is a Pre-Dart-3 Design.*
