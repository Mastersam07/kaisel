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

// A modal flow returning a typed result.
final class ConfirmPurchase extends AppRoute
    implements GateModalRoute<bool> {
  const ConfirmPurchase(this.productId);
  final String productId;
  @override
  List<Object?> get props => [productId];
}

final router = GateRouter<AppRoute>(initial: const Home());

await router.push(const ProductDetail('sku-42'));
final confirmed = await router.run(ConfirmPurchase('sku-42'));
if (confirmed == true) /* ... */
```

## Why

The two dominant Flutter routing libraries — `go_router` and `auto_route` — were architected before Dart 3 and still organize themselves around a string-path primitive (`'/products/:id'`). Type safety is bolted on with `build_runner`. The URL becomes the source of truth for route definitions, even on mobile-only apps that don't use URLs.

Dart 3 has had the type machinery to do better since 2023: sealed classes, exhaustive pattern matching, records. `gate` is what a routing library looks like when you start from those primitives instead of working around their absence.

The architectural posture, in one line: **the route stack is a `List<R>`, navigation is list manipulation, the URL is an optional codec on top, guards are pure functions in a pipeline, and modal flows are sub-routers with typed result completers.**

## What you get in v0.3

- **Typed route stack** as `List<R>` over your sealed class.
- **Default value equality** via `props`. No manual `==`/`hashCode`. No codegen.
- **Guard pipeline** — `FutureOr<List<R>> Function(current, proposed)`. Composable, async-aware, pure-Dart testable.
- **Shells** — `GateShell<R>` for tab/bottom-nav with per-branch back stacks, scoped state, and proper back-button handling.
- **Modal sub-flows with typed results** — `await router.run<T>(SomeFlow())` returns `Future<T?>`. The flow has its own internal stack; screens call `context.completeFlow<T>(value)` to resolve the awaiter.
- **Multi-route URL codec** — `GateStackCodec<R>` so a single URL can restore a deep stack (back button has somewhere sensible to go on deep links).
- **Unified `context.router<R>()`** — resolves to the flow router inside a modal, the branch router inside a shell, the main router elsewhere.
- **Pattern-matched page resolution** with compile-time exhaustiveness checking.
- **Identity-preserving stack diff** — pushing one route doesn't rebuild others.
- **Pure-Dart unit tests** for navigation state (no widget tree needed).

## Deliberately not in v0.3

Coming in v0.4:

- Composable `RouteModule`s mountable at URL prefixes.
- Adaptive layout policies on routes (master-detail responsive).
- Direction-aware and shared-element transitions.
- Per-branch typed route subtypes inside a shell.
- Nested modal flows.
- Per-branch URLs reaching into shell stacks.

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
    pageBuilder: (context, route) => switch (route) { /* ... */ },
    chromeBuilder: (context, active, branchContent, switchBranch) => Scaffold(
      body: branchContent,
      bottomNavigationBar: NavigationBar(
        selectedIndex: active,
        onDestinationSelected: switchBranch,
        destinations: const [/* ... */],
      ),
    ),
  ),
},
```

Inside any branch screen:

```dart
context.router<AppRoute>().push(const ProductDetail('42')); // resolves to branch router
context.shellRouter<AppRoute>().switchTo(2);                 // change tab
```

Each branch keeps its own back stack (via `IndexedStack`); Android back unwinds the active branch first; only at branch root does back fall through to the parent router.

### 5. Modal flows with typed results

A modal flow is a route variant on your sealed hierarchy that *also* implements `GateModalRoute<T>` to declare its result type:

```dart
final class ConfirmAddToCart extends AppRoute
    implements GateModalRoute<int> {
  const ConfirmAddToCart(this.productId);
  final String productId;
  @override
  List<Object?> get props => [productId];
}
```

Run the flow and `await` its result:

```dart
final qty = await router.run(ConfirmAddToCart('sku-42'));
if (qty != null) {
  // user confirmed with qty
}
```

Pass a `modalBuilder` to the delegate to render the flow's UI over the main app:

```dart
GateRouterDelegate<AppRoute>(
  router: router,
  builder: _buildPage,
  modalBuilder: (context, flowRoute, flowChild) => Material(
    color: Colors.black54,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: Material(
          clipBehavior: Clip.hardEdge,
          borderRadius: BorderRadius.circular(16),
          child: flowChild,
        ),
      ),
    ),
  ),
);
```

Inside the flow's screens, push within the flow via `context.router<AppRoute>().push(...)` (which resolves to the flow's sub-router) and resolve the awaiter via `context.completeFlow<int>(qty)` or `context.dismissFlow()`.

Run modal flows on the **main** router — branch routers don't have a delegate to render the overlay.

### 6. URLs (optional, multi-route)

If you target web or want deep links, implement a `GateStackCodec`:

```dart
class AppStackCodec implements GateStackCodec<AppRoute> {
  const AppStackCodec();

  @override
  Uri encode(List<AppRoute> stack) => switch (stack.last) {
    Home() => Uri(path: '/'),
    ProductDetail(:final id) => Uri(path: '/products/$id'),
    Settings() => Uri(path: '/settings'),
  };

  @override
  List<AppRoute>? decode(Uri uri) => switch (uri.pathSegments) {
    [] || [''] => const [Home()],
    ['products', final id] => [const Home(), ProductDetail(id)],
    ['settings'] => const [Home(), Settings()],  // deep restore
    _ => null,
  };
}
```

`/settings` decodes to a 2-deep stack so back goes home. Pass it to the parser:

```dart
routeInformationParser: GateRouteInformationParser<AppRoute>(
  codec: const AppStackCodec(),
  fallback: const [Home()],
),
```

Migrating from v0.2's single-route codec? Either implement the new interface, or wrap with `GateRouteInformationParser<R>.single(codec: ..., fallback: ...)` for source compatibility.

If you don't need URLs, don't implement the codec.

## Why no equality codegen

Routing libraries that bake in `freezed` force codegen on every consumer. `gate` provides default `props`-based equality on `GateRoute` itself, so the common case is a one-line override. If you want `freezed sealed`, that still works — your override wins. If you want Equatable, declare your routes with `extends GateRoute with EquatableMixin`. The library doesn't impose a choice.

## Status

v0.3 is the production-shaped surface — routes, guards, shells, modal flows with typed results, multi-route URLs. Public API will be stable for the v0.3.x line. v0.4 adds route modules and adaptive layout on top of this core.

## Comparison

For a longer-form motivation, see the companion article: *Flutter Routing Is a Pre-Dart-3 Design.*
