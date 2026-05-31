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

The architectural posture, in one line: **the route stack is a `List<R>`, navigation is list manipulation, the URL is an optional codec on top, guards are pure functions in a pipeline, modal flows are sub-routers with typed result completers, and features ship as composable `RouteModule`s mounted at marker routes.**

## What you get in v0.6

- **Typed route stack** as `List<R>` over your sealed class.
- **Default value equality** via `props`. No manual `==`/`hashCode`. No codegen.
- **Guard pipeline** — `FutureOr<List<R>> Function(current, proposed)`. Composable, async-aware, pure-Dart testable.
- **Shells** — `GateShell<R>` (homogeneous branches) and `GateBranchedShell` (per-branch typed routes), both with per-tab back stacks, scoped state, and proper back-button handling.
- **Composable `RouteModule`s** (new in v0.6) — package a feature's routes as a `const`-friendly unit with its own sealed subtype, page builder, and guards. Mount with `GateModuleMount<R>`; the host's codec assembles URLs at whatever prefix it chooses.
- **URL-addressable shell *and* module state** — a URL like `/home/products/sku-42` deep-links into a branch stack; `/checkout/confirm` deep-links into a module's stack. Inactive branches keep their in-memory state across tab switches; modules keep theirs until unmounted.
- **Modal sub-flows with typed results** — `await router.run<T>(SomeFlow())` returns `Future<T?>`. The flow has its own internal stack; screens call `context.completeFlow<T>(value)` to resolve the awaiter.
- **`GateConfigCodec<R>`** — the v0.5+ codec interface, parameterised by `GateConfig<R>` (main stack + optional shell *or* module state). A `StackToConfigCodec` adapter wraps v0.4 codecs unchanged.
- **Unified `context.router<R>()`** — resolves to the flow router inside a modal, the branch router inside a branched shell, the module router inside a mount, the main router elsewhere.
- **Pattern-matched page resolution** with compile-time exhaustiveness checking.
- **Identity-preserving stack diff** — pushing one route doesn't rebuild others.
- **Pure-Dart unit tests** for navigation state (no widget tree needed).

## Deliberately not in v0.6

Coming in v0.7+:

- Adaptive layout policies on routes (master-detail responsive).
- Direction-aware and shared-element transitions.
- Nested modal flows (relaxing the v0.3 "one flow at a time" constraint).
- A composition helper for prefix-based module URL routing (the host's codec currently assembles module URLs by hand).

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

Two shell flavours, picked based on how strictly you want per-tab typing.

**`GateShell<R>`** — all branches share one route type. Simpler for small apps.

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

Inside a branch screen with this flavour, `context.router<AppRoute>()` returns the active branch's router and `context.shellRouter<AppRoute>()` returns the shell aggregator.

**`GateBranchedShell`** (v0.4) — each branch has its own sealed type. Pushing a route from the wrong tab is a compile error.

```dart
sealed class HomeRoute extends GateRoute { const HomeRoute(); }
final class HomeRoot extends HomeRoute { const HomeRoot(); }
final class ProductDetail extends HomeRoute {
  const ProductDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

sealed class DiscoverRoute extends GateRoute { const DiscoverRoute(); }
// ...

// In your shell widget's state:
final homeRouter = GateRouter<HomeRoute>(initial: const HomeRoot());
final discoverRouter = GateRouter<DiscoverRoute>(initial: const DiscoverRoot());
final shell = BranchedShellRouter(branches: [homeRouter, discoverRouter]);

GateBranchedShell(
  shell: shell,
  branches: [
    GateBranch<HomeRoute>(
      router: homeRouter,
      pageBuilder: (context, route) => switch (route) {
        HomeRoot() => const HomeScreen(),
        ProductDetail(:final id) => ProductDetailScreen(id: id),
      },
    ),
    GateBranch<DiscoverRoute>(
      router: discoverRouter,
      pageBuilder: (context, route) => switch (route) { /* ... */ },
    ),
  ],
  chromeBuilder: (context, active, branchContent, switchBranch) => Scaffold(
    body: branchContent,
    bottomNavigationBar: NavigationBar(
      selectedIndex: active,
      onDestinationSelected: switchBranch,
      destinations: const [/* ... */],
    ),
  ),
)
```

Inside a Home branch screen:

```dart
context.router<HomeRoute>().push(const ProductDetail('42'));      // typed
context.router<AppRoute>().push(const Settings());                // main router
context.branchedShell().switchTo(2);                              // change tab
```

`context.router<HomeRoute>()` and `context.router<AppRoute>()` don't collide — `RouterScope` lookup is by exact generic type, so different `R`s shadow only their own scope.

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

### 6. URLs (optional)

If you target web or want deep links, implement a codec. Two interfaces, picked based on whether you need URLs to address state inside a branched shell.

**`GateStackCodec<R>`** — stack-only URLs, unchanged from v0.4. Pattern-match on the main router's stack:

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

Wire via `.fromStackCodec`:

```dart
routeInformationParser: GateRouteInformationParser<AppRoute>.fromStackCodec(
  codec: const AppStackCodec(),
  fallback: const [Home()],
),
```

**`GateConfigCodec<R>`** — URLs that reach into a nested router (a `GateBranchedShell` or a `GateModuleMount`). The configuration carries the main stack plus an optional `nestedState`, which is a sealed `GateNestedConfig` — either `GateShellConfig` or `GateModuleConfig`:

```dart
class AppCodec implements GateConfigCodec<AppRoute> {
  const AppCodec();

  @override
  Uri encode(GateConfig<AppRoute> config) {
    return switch ((config.mainStack.last, config.nestedState)) {
      (Splash(), _)   => Uri(path: '/'),
      (Settings(), _) => Uri(path: '/settings'),
      (MainShell(), final GateShellConfig shell) => _encodeShell(shell),
      (MainShell(), _) => Uri(path: '/home'),
      _ => Uri(path: '/'),
    };
  }

  Uri _encodeShell(GateShellConfig shell) => switch (shell.activeBranch) {
    0 => switch (shell.activeBranchStack) {
      [HomeRoot()] => Uri(path: '/home'),
      [HomeRoot(), ProductDetail(:final id)] => Uri(path: '/home/products/$id'),
      _ => Uri(path: '/home'),
    },
    1 => Uri(path: '/discover'),
    _ => Uri(path: '/home'),
  };

  @override
  GateConfig<AppRoute>? decode(Uri uri) => switch (uri.pathSegments) {
    [] || [''] => GateConfig(mainStack: const [Splash()]),
    ['home'] => GateConfig(
      mainStack: const [MainShell()],
      nestedState: GateShellConfig(
        activeBranch: 0,
        activeBranchStack: const [HomeRoot()],
      ),
    ),
    ['home', 'products', final id] => GateConfig(
      mainStack: const [MainShell()],
      nestedState: GateShellConfig(
        activeBranch: 0,
        activeBranchStack: [const HomeRoot(), ProductDetail(id)],
      ),
    ),
    _ => null,
  };
}
```

Wire via the regular constructor:

```dart
routeInformationParser: GateRouteInformationParser<AppRoute>(
  codec: const AppCodec(),
  fallback: const [Splash()],
),
```

`/home/products/sku-42` deep-links into the Home branch with `ProductDetail('sku-42')` on top of `HomeRoot()`. Switching tabs preserves each branch's stack (inactive branches stay off the URL but in memory).

If you don't need URLs, don't implement either codec.

### 7. Modules (v0.6)

A `RouteModule` packages a feature's routes as a `const`-friendly unit: its own sealed subtype, its own page builder, its own optional guards. The host mounts it with `GateModuleMount<R>` at a top-level route, and the host's codec decides how the module's URLs are assembled. The module doesn't know about the host's prefix.

```dart
sealed class CheckoutRoute extends GateRoute { const CheckoutRoute(); }
final class CheckoutCart extends CheckoutRoute { const CheckoutCart(); }
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
        CheckoutCart() => const CheckoutCartScreen(),
        CheckoutShipping() => const CheckoutShippingScreen(),
        CheckoutConfirm() => const CheckoutConfirmScreen(),
      };
}
```

Mount it from the host's page builder via a marker route in your `AppRoute`:

```dart
final class CheckoutMount extends AppRoute { const CheckoutMount(); }

Widget _buildMainPage(BuildContext context, AppRoute route) =>
    switch (route) {
      CheckoutMount() => const GateModuleMount<CheckoutRoute>(
          module: CheckoutModule(),
        ),
      // ... other top-level routes
    };
```

Inside the module's screens, `context.router<CheckoutRoute>()` resolves to the module's typed router — pushing a `CheckoutShipping` typechecks; pushing an `AppRoute` is a compile error. `context.router<AppRoute>()` bypasses this scope and finds the host router above (same lookup-by-exact-type semantics as branched shells), which is how the module exits itself: `context.router<AppRoute>().pop()` pops `CheckoutMount` off the main stack.

URLs are wired through the host's `GateConfigCodec`. A deep link to `/checkout/confirm` restores the full module stack `[Cart, Shipping, Confirm]` so back unwinds through the flow:

```dart
GateConfig<AppRoute>? decode(Uri uri) => switch (uri.pathSegments) {
  ['checkout'] => _moduleAt(const [CheckoutCart()]),
  ['checkout', 'shipping'] =>
    _moduleAt(const [CheckoutCart(), CheckoutShipping()]),
  ['checkout', 'confirm'] => _moduleAt(
      const [CheckoutCart(), CheckoutShipping(), CheckoutConfirm()],
    ),
  // ...
};

GateConfig<AppRoute> _moduleAt(List<GateRoute> stack) => GateConfig(
      mainStack: const [CheckoutMount()],
      nestedState: GateModuleConfig(stack: stack),
    );
```

`GateConfig<R>.nestedState` is a sealed `GateNestedConfig` — either a `GateShellConfig` or a `GateModuleConfig`. The type system guarantees you can carry at most one nested kind on top of the main stack; no runtime assertion is needed. Pattern-match in your codec's `encode` to dispatch by `(topRoute, nestedState)`.

## Why no equality codegen

Routing libraries that bake in `freezed` force codegen on every consumer. `gate` provides default `props`-based equality on `GateRoute` itself, so the common case is a one-line override. If you want `freezed sealed`, that still works — your override wins. If you want Equatable, declare your routes with `extends GateRoute with EquatableMixin`. The library doesn't impose a choice.

## Status

v0.6 is the current development line. The core surface — routes, guards, shells (homogeneous and per-branch typed), modal flows with typed results, URL-addressable shell and module state, composable modules — is in place. Adaptive layouts, direction-aware transitions, and nested modal flows are tracked for v0.7+. Public API is shaped for stability but not frozen.

## Comparison

For a longer-form motivation, see the companion article: *Flutter Routing Is a Pre-Dart-3 Design.*
