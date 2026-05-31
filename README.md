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

The two dominant Flutter routing libraries (`go_router` and `auto_route`) were architected before Dart 3 and still organize themselves around a string-path primitive (`'/products/:id'`). Type safety is bolted on with `build_runner`. The URL becomes the source of truth for route definitions, even on mobile-only apps that don't use URLs.

Dart 3 has had the type machinery to do better since 2023: sealed classes, exhaustive pattern matching, records. `gate` is what a routing library looks like when you start from those primitives instead of working around their absence.

The architectural posture, in one line: **the route stack is a `List<R>`, navigation is list manipulation, the URL is an optional codec on top, guards are pure functions in a pipeline, modal flows are sub-routers with typed result completers, and features ship as composable `RouteModule`s mounted at marker routes.**

## What you get in v0.10

- **Typed route stack** as `List<R>` over your sealed class.
- **Default value equality** via `props`. No manual `==`/`hashCode`. No codegen.
- **Guard pipeline**: `FutureOr<List<R>> Function(current, proposed)`. Composable, async-aware, pure-Dart testable.
- **Shells**: `GateShell<R>` (homogeneous branches) and `GateBranchedShell` (per-branch typed routes), both with per-tab back stacks, scoped state, and proper back-button handling.
- **Composable `RouteModule`s**: package a feature's routes as a `const`-friendly unit with its own sealed subtype, page builder, guards, and (since v0.7) URL codec. Mount with `GateModuleMount<R>`.
- **URL-addressable shell *and* module state**: a URL like `/home/products/sku-42` deep-links into a branch stack; `/checkout/confirm` deep-links into a module's stack. Inactive branches keep their in-memory state across tab switches; modules keep theirs until unmounted.
- **Module URL composition** (since v0.7). Modules ship their own `ModuleStackCodec`; the host composes URL routing via `ConfigCodecWithModules` without duplicating each module's URL structure in its main codec. The host's main codec stays module-agnostic.
- **Adaptive layouts** (since v0.8, extended in v0.9). At the main delegate via `GateRouterDelegate.adaptive`, inside shell branches via `GateBranch.adaptive` and `GateShell.adaptive`, and inside modules via `RouteModule.buildAdaptivePage` + `isAdaptive`. A detail route can return `GateAbsorbingPage` to collapse master+detail into a single rendered page (master-detail without changing the stack model). Page identity is keyed on the lowest absorbed entry so selecting a different detail doesn't trigger a Navigator transition.
- **Modal sub-flows with typed results**: `await router.run<T>(SomeFlow())` returns `Future<T?>`. The flow has its own internal stack; screens call `context.completeFlow<T>(value)` to resolve the awaiter. **Flows can nest** (new in v0.10): each nested flow gets its own sub-router and modal layer, and completions unwind LIFO.
- **`GateConfigCodec<R>`**: the v0.5+ codec interface, parameterised by `GateConfig<R>` (main stack + optional shell *or* module state). A `StackToConfigCodec` adapter wraps v0.4 codecs unchanged.
- **Unified `context.router<R>()`**: resolves to the flow router inside a modal, the branch router inside a branched shell, the module router inside a mount, the main router elsewhere.
- **Pattern-matched page resolution** with compile-time exhaustiveness checking.
- **Identity-preserving stack diff**: pushing one route doesn't rebuild others.
- **Pure-Dart unit tests** for navigation state (no widget tree needed).

## Deliberately not in v0.10

Coming in future versions:

- Direction-aware and shared-element transitions. Requires a breaking change to `GatePageWrapper`'s signature.

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

No-field variants get equality automatically (`Home() == Home()`). Variants with fields override `props`. If you need different equality semantics, override `==` and `hashCode` directly. Your override wins.

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

Sync or async. Async guards make the navigation async, sync ones complete synchronously. Each guard either allows (return proposed), redirects (return something different), or refuses (return current).

Guards do **not** run on system back. The pop has already animated by the time we hear about it; running guards there would cause visible jumps. State-driven redirects (e.g. force back to login on logout) should be listeners on app state that call `router.set` directly.

### 4. Shells (bottom-nav with per-tab state)

Two shell flavours, picked based on how strictly you want per-tab typing.

**`GateShell<R>`**: all branches share one route type. Simpler for small apps.

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

**`GateBranchedShell`** (v0.4). Each branch has its own sealed type. Pushing a route from the wrong tab is a compile error.

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

`context.router<HomeRoute>()` and `context.router<AppRoute>()` don't collide; `RouterScope` lookup is by exact generic type, so different `R`s shadow only their own scope.

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

Run modal flows on the **main** router. Branch routers don't have a delegate to render the overlay.

**Nested flows** (since v0.10): a flow can itself call `router.run<T>(...)` to launch another flow on top of it. Each nested flow gets its own sub-router and its own modal overlay layer. `context.completeFlow<T>(value)` from inside any flow resolves the topmost one. To unwind multiple layers, complete the topmost, await it, then complete the next. `router.activeFlows` exposes the full stack if you need to inspect or render based on depth.

```dart
// Inside an outer flow's screen:
final verified = await router.run<bool>(VerifyIdentityFlow());
if (verified == true) {
  context.completeFlow<bool>(true);  // resolves the outer flow
}
```

### 6. URLs (optional)

If you target web or want deep links, implement a codec. Two interfaces, picked based on whether you need URLs to address state inside a branched shell.

**`GateStackCodec<R>`**: stack-only URLs, unchanged from v0.4. Pattern-match on the main router's stack:

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

**`GateConfigCodec<R>`**: URLs that reach into a nested router (a `GateBranchedShell` or a `GateModuleMount`). The configuration carries the main stack plus an optional `nestedState`, which is a sealed `GateNestedConfig`, either `GateShellConfig` or `GateModuleConfig`:

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

### 7. Modules

A `RouteModule` packages a feature's routes as a `const`-friendly unit: its own sealed subtype, its own page builder, its own optional guards, and (v0.7) its own optional URL codec. The host mounts the module at a top-level route and composes URL routing via `ConfigCodecWithModules`. The module doesn't know what prefix the host will mount it at.

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

  @override
  ModuleStackCodec<CheckoutRoute>? get codec =>
      const CheckoutModuleCodec();
}

class CheckoutModuleCodec extends ModuleStackCodec<CheckoutRoute> {
  const CheckoutModuleCodec();

  @override
  List<String> encode(List<CheckoutRoute> stack) => switch (stack.last) {
    CheckoutCart() => const [],          // root: prefix alone
    CheckoutShipping() => const ['shipping'],
    CheckoutConfirm() => const ['confirm'],
  };

  @override
  List<CheckoutRoute>? decode(List<String> segments) => switch (segments) {
    [] => const [CheckoutCart()],
    ['shipping'] => const [CheckoutCart(), CheckoutShipping()],
    ['confirm'] => const [
      CheckoutCart(), CheckoutShipping(), CheckoutConfirm(),
    ],
    _ => null,
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

Inside the module's screens, `context.router<CheckoutRoute>()` resolves to the module's typed router. Pushing a `CheckoutShipping` typechecks; pushing an `AppRoute` is a compile error. `context.router<AppRoute>()` bypasses this scope and finds the host router above (same lookup-by-exact-type semantics as branched shells), which is how the module exits itself: `context.router<AppRoute>().pop()` pops `CheckoutMount` off the main stack.

Wire URLs via the composer. The host's main codec stays module-agnostic, and the module's codec handles paths under whatever prefix the host declares:

```dart
const appCodec = ConfigCodecWithModules<AppRoute>(
  baseCodec: _MainAppCodec(),
  modules: [
    ModuleMount(
      mountRoute: CheckoutMount(),
      prefix: '/checkout',
      codec: CheckoutModuleCodec(),
    ),
  ],
);
```

A deep link to `/checkout/confirm` restores the full module stack `[Cart, Shipping, Confirm]` so back unwinds through the flow. Adding another module means appending to `modules`. No edits to the main codec.

`GateConfig<R>.nestedState` is a sealed `GateNestedConfig`, either a `GateShellConfig` or a `GateModuleConfig`. The type system guarantees you can carry at most one nested kind on top of the main stack; no runtime assertion is needed. Pattern-match in your codec's `encode` to dispatch by `(topRoute, nestedState)`.

### 8. Adaptive layouts

Adaptive layouts let one route render a widget that subsumes one or more entries below it on the stack. The canonical use is master-detail at wide breakpoints: the detail route absorbs the master into a single rendered page. The stack stays the same; only the rendering changes.

The page builder returns a `GatePageResult`: either `GateStandalonePage(widget)` (default 1:1) or `GateAbsorbingPage(widget, absorbing: n)`, which renders a widget that subsumes `n` entries below it on the stack.

Adaptive builders run at three levels: the main delegate (v0.8), shell branches and modules (v0.9). All three share the same `GatePageResult` API, the same page-identity semantics, and the same back-button behaviour. Pick the level that matches where the master-detail lives.

**At the main delegate (v0.8):**

```dart
GateRouterDelegate<AppRoute>.adaptive(
  router: router,
  builder: (context, route, stack) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return switch ((route, stack.previous, wide)) {
      (ProductDetail(:final id), ProductList(:final category), true) =>
        GateAbsorbingPage(
          widget: GateMasterDetailScaffold(
            master: ProductListScreen(category: category),
            detail: ProductDetailScreen(id: id),
          ),
        ),
      _ => GateStandalonePage(buildSimple(route)),
    };
  },
);
```

**Inside a shell branch (v0.9):**

Use `GateBranch.adaptive` for `GateBranchedShell` (heterogeneous branches), or `GateShell.adaptive` for the homogeneous shell. The branch's inner navigator goes through the adaptive pipeline; entries within that branch's stack can be absorbed.

```dart
GateBranchedShell(
  shell: shell,
  branches: [
    GateBranch<HomeRoute>.adaptive(
      router: homeRouter,
      pageBuilder: (context, route, stack) {
        final wide = MediaQuery.sizeOf(context).width >= 700;
        return switch ((route, stack.previous, wide)) {
          (ProductDetail(:final id), ProductList(), true) =>
            GateAbsorbingPage(
              widget: GateMasterDetailScaffold(
                master: const ProductListScreen(),
                detail: ProductDetailScreen(id: id),
              ),
            ),
          _ => GateStandalonePage(buildSimple(route)),
        };
      },
    ),
    // Other branches stay simple if they don't need adaptive.
    GateBranch<DiscoverRoute>(router: discoverRouter, pageBuilder: ...),
  ],
  chromeBuilder: ...,
);
```

**Inside a module (v0.9):**

Override `RouteModule.buildAdaptivePage` and set `isAdaptive` to `true`. The default `buildAdaptivePage` wraps `buildPage` as a standalone page, so unmodified modules behave exactly as before.

```dart
class ShopModule extends RouteModule<ShopRoute> {
  const ShopModule();

  @override
  bool get isAdaptive => true;

  @override
  Widget buildPage(BuildContext context, ShopRoute route) => switch (route) {
    ShopList() => const ShopListScreen(),
    ShopDetail(:final sku) => ShopDetailScreen(sku: sku),
  };

  @override
  GatePageResult buildAdaptivePage(
    BuildContext context,
    ShopRoute route,
    GateStackContext<ShopRoute> stack,
  ) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return switch ((route, stack.previous, wide)) {
      (ShopDetail(:final sku), ShopList(), true) => GateAbsorbingPage(
        widget: GateMasterDetailScaffold(
          master: const ShopListScreen(),
          detail: ShopDetailScreen(sku: sku),
        ),
      ),
      _ => GateStandalonePage(buildPage(context, route)),
    };
  }
}
```

`GateStackContext` exposes `stack`, `position`, `previous`, `next`, `isTop`, `isBottom` so the builder can pattern-match on neighbours. `GateMasterDetailScaffold` is a small convenience widget that lays out master and detail with a divider; replace it with your own if you want different chrome.

Two things worth knowing about page identity:

- Absorbing pages are keyed by the *lowest* absorbed entry's id, not the absorbing entry's. Going from `[List, DetailA]` to `[List, DetailB]` produces pages with equal keys; the Navigator doesn't animate a transition, the detail pane content just updates. Wrap the swapping content in an `AnimatedSwitcher` if you want a fade between details. Note that the transition is `replace`-shaped, not `push`-shaped: a `router.push(DetailB)` from `[List, DetailA]` produces `[List, DetailA, DetailB]` (three entries, the new top has another `Detail` below it, so the absorbing arm doesn't match and the page slides in). Use `router.replace(DetailB)` when the current top is already a detail.
- The pop target is the top absorbing entry. OS back on `[List, Detail]` absorbed pops Detail, leaving `[List]`. Back means "undo the last push" regardless of visual rendering. At the main delegate, this needs a `popRoute` override because `Navigator.maybePop` declines when there's only one visible page (see v0.8 changelog). At the shell branch and module level, `PopScope` calls `router.pop()` directly, so absorbing-collapsed-to-1-page is handled by construction.

## Why no equality codegen

Routing libraries that bake in `freezed` force codegen on every consumer. `gate` provides default `props`-based equality on `GateRoute` itself, so the common case is a one-line override. If you want `freezed sealed`, that still works. Your override wins. If you want Equatable, declare your routes with `extends GateRoute with EquatableMixin`. The library doesn't impose a choice.

## Status

v0.10 is the current development line. The core surface (routes, guards, shells in both homogeneous and per-branch typed forms, modal flows with typed results and nesting, URL-addressable shell and module state, composable modules, module URL composition, and adaptive layouts at the main delegate, shell branches, and module mounts) is in place. Direction-aware transitions are tracked for future versions. Public API is shaped for stability but not frozen.

## Comparison

For a longer-form motivation, see the companion article: *Flutter Routing Is a Pre-Dart-3 Design.*