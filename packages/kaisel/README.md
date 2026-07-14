# kaisel
[![Test](https://github.com/Mastersam07/kaisel/actions/workflows/ci.yml/badge.svg?branch=dev)](https://github.com/Mastersam07/kaisel/actions/workflows/ci.yml)
[![codecov](https://codecov.io/github/Mastersam07/kaisel/branch/dev/graph/badge.svg?token=tHYIe4iPGo)](https://codecov.io/github/Mastersam07/kaisel)

A Dart 3-native Flutter router built on sealed routes, pattern matching, and a stack-as-state model. **No string paths. No codegen.**

```dart
sealed class AppRoute extends KaiselRoute {
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
    implements KaiselModalRoute<bool> {
  const ConfirmPurchase(this.productId);
  final String productId;
  @override
  List<Object?> get props => [productId];
}

final router = KaiselRouter<AppRoute>(initial: const Home());

await router.push(const ProductDetail('sku-42'));
final confirmed = await router.run(ConfirmPurchase('sku-42'));
if (confirmed == true) /* ... */
```

## Why

The two dominant Flutter routing libraries (`go_router` and `auto_route`) were architected before Dart 3 and still organize themselves around a string-path primitive (`'/products/:id'`). Type safety is bolted on with `build_runner`. The URL becomes the source of truth for route definitions, even on mobile-only apps that don't use URLs.

Dart 3 has had the type machinery to do better since 2023: sealed classes, exhaustive pattern matching, records. `kaisel` is what a routing library looks like when you start from those primitives instead of working around their absence:

> The route stack is a `List<R>`, navigation is list manipulation, the URL is an optional codec on top, guards are pure functions in a pipeline, modal flows are sub-routers with typed result completers, and features ship as composable `RouteModule`s mounted at marker routes.

## Features

- **Typed route stack** — `List<R>` over your sealed class. Pattern-matched page resolution with compile-time exhaustiveness.
- **One-line setup, typed navigation** — `KaiselRouterConfig` collapses the router, delegate, and parser into a single `routerConfig:`; navigate with the typed `context.router<R>().push` / `pop` / `replaceTop` / `pushOrReplaceTop` / `set` / `pushForResult<T>` / `run<T>` (a wrong-family route is a compile error), or the terser `context.push(...)` when you'll take a runtime family check for the brevity.
- **Value equality for free** — default `props`-based `==`/`hashCode` on `KaiselRoute`. No manual equality, no codegen.
- **Guard pipeline** — composable `FutureOr<List<R>> Function(current, proposed)` functions. Async-aware and pure-Dart testable.
- **Shells** — `KaiselShell<R>` (homogeneous branches) and `KaiselBranchedShell` (per-branch typed routes; `.specs` declares branches without wiring routers), with per-tab back stacks, scoped state, and correct back-button handling. One `context.shell()` accessor drives either. Opt into `lazy: true` to build tabs on first visit (kept alive after), and `KaiselBranchSpec.deferred` to code-split a tab's screens behind a `deferred as` import — with a placeholder, error builder, and retry.
- **Composable modules** — package a feature's routes, page builder, guards, and URL codec as a `const`-friendly `RouteModule`. Mount with `KaiselModuleMount<R>`; compose URLs with `ConfigCodecWithModules` without the host knowing the module's internal structure.
- **URL-addressable** — deep-link into a branch stack (`/home/products/sku-42`) or a module stack (`/checkout/confirm`). Inactive branches keep in-memory state across tab switches.
- **Typed results, two ways** — `await context.pushForResult<T>(SomeScreen())` keeps the screen on the **main stack** (a normal route — observed, with root dialogs above it) and resolves when it pops with `context.pop(result)`. `await router.run<T>(SomeFlow())` lifts a multi-screen **modal flow** into its own sub-router; flows can nest, unwinding LIFO.
- **Adaptive layouts** — at the main delegate, inside shell branches, and inside modules. A detail route can absorb its master into one rendered page (master-detail without changing the stack model).
- **Direction-aware transitions** — pattern-match on the `(previous, current)` route pair to pick a `Page` subclass per transition. Web-friendly fade by default. Shared elements via Flutter's `Hero`.
- **Navigator observers** — attach `NavigatorObserver`s (analytics, Sentry, `RouteObserver`) with an `observers: () => [...]` builder. It's called once per navigator — the main stack and each shell branch, module, and flow — so every navigator gets its own fresh instance. Every navigation reaches them, including tab switches and adaptive in-place changes, which produce no Navigator route event of their own.
- **`KaiselPageScope` for descendants** — deeply-nested widgets read the page's position in the rendered stack (`isTop`, `isBottom`, `previous`, …) without prop-drilling.
- **Identity-preserving stack diff** — pushing one route doesn't rebuild the others.
- **Pure-Dart unit tests** for navigation state — no widget tree needed.

## Usage

### 1. Declare your route type

```dart
sealed class AppRoute extends KaiselRoute {
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

No-field variants get equality automatically (`Home() == Home()`). Variants with fields override `props`. If you need different semantics, override `==` and `hashCode` directly — your override wins.

### 2. Wire it up

Bundle the router into a `KaiselRouterConfig` and hand it to `MaterialApp.router` — no `StatefulWidget`, no manual delegate or parser, no `dispose`:

```dart
// Hold it as a top-level `final` for an app-lifetime router.
final _config = KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  builder: (context, route) => switch (route) {
    Home() => const HomeScreen(),
    ProductDetail(:final id) => ProductDetailScreen(id: id),
  },
);

void main() => runApp(MaterialApp.router(routerConfig: _config));
```

Add a variant and the switch fails to compile until you handle it. That's the entire point.

`_config.router` is the underlying `KaiselRouter<AppRoute>` for imperative navigation outside the tree; pass `codec:` to make the app URL-addressable ([§6](#6-urls-optional)). For full control you can still construct the `KaiselRouterDelegate` and parser yourself — `KaiselRouterConfig` is the convenience layer over them.

Need a raw `GlobalKey<NavigatorState>` (for a third-party SDK, or `Navigator.of`-style overlays without a `BuildContext`)? Pass `navigatorKey:` to the config, or read the auto-created one via `_config.navigatorKey` / `_config.navigator`. For *navigation* itself, prefer `_config.router` — it's the context-free handle.

### 3. Guards

Guards are `FutureOr<List<R>> Function(current, proposed)`. They run in order, each receiving the previous's output:

```dart
KaiselGuard<AppRoute> authGuard(ValueListenable<bool> loggedIn) {
  return (current, proposed) {
    final needsAuth = proposed.any((r) => r is RequiresAuth);
    if (needsAuth && !loggedIn.value) return const [Login()];
    return proposed;
  };
}

final router = KaiselRouter<AppRoute>(
  initial: const Home(),
  guards: [authGuard(authNotifier)],
);
```

Each guard either allows (return `proposed`), redirects (return something different), or refuses (return `current`). Sync guards complete synchronously; async guards make the navigation async.

To **redirect to login and then continue** to where the user was headed, stash the `proposed` stack before redirecting and replay it with `router.set` after login — the intended destination is plain `List<R>` data, so the *whole* intended stack (Cart under Payment, back and all) is reconstructed, not just the final screen. The same guard handles deep links into protected routes. See [`example/lib/main_auth_redirect.dart`](example/lib/main_auth_redirect.dart).

Guards do **not** run on system back — the pop has already animated by the time we hear about it. State-driven redirects (e.g. force back to login on logout) should be app-state listeners that call `router.set` directly.

### 4. Shells (bottom-nav with per-tab state)

Two flavours, picked by how strictly you want per-tab typing.

**`KaiselShell<R>`** — all branches share one route type `R`. Simpler for small apps. **`R` must be a sealed type scoped to the shell's own routes, not your app-wide `AppRoute`:** the `pageBuilder` switch is exhaustive over `R`, so switching over the whole `AppRoute` would force you to handle every variant the app has, not just the tabs.

```dart
// A sealed type for just the shell's branches (mounted at MainShell).
sealed class TabRoute extends KaiselRoute { const TabRoute(); }
final class HomeRoot extends TabRoute { const HomeRoot(); }
final class DiscoverRoot extends TabRoute { const DiscoverRoot(); }
final class ProfileRoot extends TabRoute { const ProfileRoot(); }

builder: (context, route) => switch (route) {
  MainShell() => KaiselShell<TabRoute>(
    branchInitials: const [HomeRoot(), DiscoverRoot(), ProfileRoot()],
    pageBuilder: (context, route) => switch (route) {
      HomeRoot() => const HomeScreen(),
      DiscoverRoot() => const DiscoverScreen(),
      ProfileRoot() => const ProfileScreen(),
    }, // exhaustive over TabRoute — add a variant here for anything a tab pushes
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

Inside a branch screen, `context.router<TabRoute>()` returns the active branch's router and `context.shell()` returns the shell controller (`switchTo`, `activeBranch`, `current`). (When tabs need *different* route types, reach for `KaiselBranchedShell` below instead.)

**`KaiselBranchedShell`** — each branch has its own sealed type. Pushing a route from the wrong tab is a compile error.

```dart
sealed class HomeRoute extends KaiselRoute { const HomeRoute(); }
final class HomeRoot extends HomeRoute { const HomeRoot(); }
final class ProductDetail extends HomeRoute {
  const ProductDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

sealed class DiscoverRoute extends KaiselRoute { const DiscoverRoute(); }
// ...

// Declare the branches — the shell creates, owns, and disposes one router per
// branch. You never construct a KaiselRouter, and each branch's stack still
// survives tab switches.
KaiselBranchedShell.specs(
  branches: [
    KaiselBranchSpec<HomeRoute>(
      initial: const HomeRoot(),
      builder: (context, route) => switch (route) {
        HomeRoot() => const HomeScreen(),
        ProductDetail(:final id) => ProductDetailScreen(id: id),
      },
    ),
    KaiselBranchSpec<DiscoverRoute>(
      initial: const DiscoverRoot(),
      builder: (context, route) => switch (route) { /* ... */ },
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

Use `KaiselBranchSpec.adaptive(...)` for an adaptive branch. When you need to hold the branch routers yourself, the explicit `KaiselBranchedShell(shell: BranchedShellRouter(...), branches: [KaiselBranch<R>(...)])` form stays. Pass `branchContentBuilder` to swap the default `IndexedStack` for a `PageView` or any other layout (you then own per-branch state preservation).

**Lazy and deferred branches.** Pass `lazy: true` to build each tab's screen only on first visit (kept alive afterwards) instead of all up front — handy for heavy tabs. A branch can go further and load its *code* on demand with `KaiselBranchSpec.deferred`, behind a `deferred as` import:

```dart
KaiselBranchedShell.specs(
  lazy: true,
  branches: [
    KaiselBranchSpec<HomeRoute>(initial: const HomeRoot(), builder: ...),
    KaiselBranchSpec<ReportsRoute>.deferred(
      initial: const ReportsRoot(),
      loadLibrary: reports.loadLibrary,        // the deferred import's tear-off
      placeholder: const Center(child: CircularProgressIndicator()),
      errorBuilder: (context, error, retry) => RetryTile(error, retry),
      builder: (context, route) => reports.ReportsScreen(),
    ),
  ],
  chromeBuilder: (context, active, branchContent, switchBranch) => /* ... */,
)
```

The route values stay in the main bundle, so back, URL capture, and deep links keep working while the screen code loads — the placeholder shows until it arrives, and a failed load renders `errorBuilder` (scoped to that tab) with a `retry` that re-runs the load. For a custom lazy layout, pass `lazyBranchContentBuilder` (the lazy counterpart to `branchContentBuilder`, with a `buildBranch(context, index)` callback). See [`example/lib/main_lazy_shell.dart`](example/lib/main_lazy_shell.dart).

Inside a Home branch screen:

```dart
context.router<HomeRoute>().push(const ProductDetail('42'));  // compile-checked family
context.router<AppRoute>().push(const Settings());            // the main router
context.shell().switchTo(2);                                  // change tab

// Or the terse convenience — resolves the nearest accepting router at runtime,
// so a wrong-family route throws instead of failing to compile:
context.push(const ProductDetail('42'));
```

`RouterScope` lookup is by exact generic type, so `context.router<HomeRoute>()` and `context.router<AppRoute>()` don't collide. Each branch keeps its own back stack (via `IndexedStack`); Android back unwinds the active branch first, falling through to the parent router only at branch root.

> **Inside the `chromeBuilder`, `context.router<BranchRoute>()` does not resolve** — each branch's `RouterScope` is installed *below* the chrome, and lookups only walk up. Use the `activeBranch`/`switchBranch` arguments or `context.shell()` to drive the shell, and `context.router<AppRoute>()` for the root router. The typed branch router is only reachable from that branch's own screens.

### 5. Typed results from a screen

Two ways to get a value back, depending on whether the screen should live on the main stack or in its own modal flow.

**`pushForResult<T>` — a normal screen on the main stack.** The screen is an ordinary route in the same `Navigator`, so a shared observer sees it, a root-navigator dialog renders above it, and back behaves normally. It resolves when the screen pops with a value:

```dart
final String? picked = await context.pushForResult<String>(const ColorPicker());
// inside ColorPicker:
context.pop('teal');               // resolves the awaiter with 'teal'
context.pop();                     // or null when dismissed without a value
```

The future resolves with `null` if the screen is popped without a value, replaced by `set` / `replaceTop`, or removed by system back. Reach for this when a screen just needs to hand back a value — no modal-flow machinery required.

**Modal flows — a multi-step sub-flow with its own router.** A modal flow is a route variant that *also* implements `KaiselModalRoute<T>` to declare its result type:

```dart
final class ConfirmAddToCart extends AppRoute
    implements KaiselModalRoute<int> {
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
KaiselRouterDelegate<AppRoute>(
  router: router,
  builder: _buildPage,
  modalBuilder: (context, flowRoute, flowChild) => Material(
    color: Colors.black54,
    child: Center(child: /* your modal chrome wrapping */ flowChild),
  ),
);
```

Inside the flow's screens, push within the flow via `context.router<AppRoute>().push(...)` (which resolves to the flow's sub-router) and resolve the awaiter via `context.completeFlow<int>(qty)` or `context.dismissFlow()`. Run modal flows on the **main** router — branch routers don't have a delegate to render the overlay.

**Nested flows:** a flow can itself call `router.run<T>(...)` to launch another flow on top of it. Each nested flow gets its own sub-router and modal layer. `context.completeFlow<T>(value)` resolves the topmost flow; to unwind multiple layers, complete the topmost, await it, then complete the next. `router.activeFlows` exposes the full stack.

```dart
// Inside an outer flow's screen:
final verified = await router.run<bool>(VerifyIdentityFlow());
if (verified == true) {
  context.completeFlow<bool>(true);  // resolves the outer flow
}
```

### 6. URLs (optional)

If you target web or want deep links, implement a codec. Two interfaces, picked by whether you need URLs to address state inside a branched shell or module. If you don't need URLs, implement neither.

**`KaiselStackCodec<R>`** — stack-only URLs. Pattern-match on the main router's stack:

```dart
class AppStackCodec implements KaiselStackCodec<AppRoute> {
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

// Wire via .fromStackCodec:
routeInformationParser: KaiselRouteInformationParser<AppRoute>.fromStackCodec(
  codec: const AppStackCodec(),
  fallback: const [Home()],
),
```

With `KaiselRouterConfig` you skip the parser entirely — pass the codec as `codec:` (and an optional `fallback:`) and it wires the parser plus a `PlatformRouteInformationProvider` for you:

```dart
final _config = KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  builder: _buildPage,
  codec: StackToConfigCodec<AppRoute>(const AppStackCodec()),
  fallback: const [Home()],
);
```

**`KaiselConfigCodec<R>`** — URLs that reach into a nested router (a `KaiselBranchedShell` or a `KaiselModuleMount`). The configuration carries the main stack plus an optional `nestedState`, a sealed `KaiselNestedConfig` that is either a `KaiselShellConfig` or a `KaiselModuleConfig`:

```dart
class AppCodec implements KaiselConfigCodec<AppRoute> {
  const AppCodec();

  @override
  Uri encode(KaiselConfig<AppRoute> config) =>
      switch ((config.mainStack.last, config.nestedState)) {
        (Splash(), _)   => Uri(path: '/'),
        (Settings(), _) => Uri(path: '/settings'),
        (MainShell(), final KaiselShellConfig shell) => _encodeShell(shell),
        (MainShell(), _) => Uri(path: '/home'),
        _ => Uri(path: '/'),
      };

  Uri _encodeShell(KaiselShellConfig shell) => switch (shell.activeBranch) {
    0 => switch (shell.activeBranchStack) {
      [HomeRoot()] => Uri(path: '/home'),
      [HomeRoot(), ProductDetail(:final id)] => Uri(path: '/home/products/$id'),
      _ => Uri(path: '/home'),
    },
    1 => Uri(path: '/discover'),
    _ => Uri(path: '/home'),
  };

  @override
  KaiselConfig<AppRoute>? decode(Uri uri) => switch (uri.pathSegments) {
    [] || [''] => KaiselConfig(mainStack: const [Splash()]),
    ['home'] => KaiselConfig(
      mainStack: const [MainShell()],
      nestedState: KaiselShellConfig(
        activeBranch: 0,
        activeBranchStack: const [HomeRoot()],
      ),
    ),
    ['home', 'products', final id] => KaiselConfig(
      mainStack: const [MainShell()],
      nestedState: KaiselShellConfig(
        activeBranch: 0,
        activeBranchStack: [const HomeRoot(), ProductDetail(id)],
      ),
    ),
    _ => null,
  };
}

// Wire via the regular constructor:
routeInformationParser: KaiselRouteInformationParser<AppRoute>(
  codec: const AppCodec(),
  fallback: const [Splash()],
),
```

`/home/products/sku-42` deep-links into the Home branch with `ProductDetail('sku-42')` on top of `HomeRoot()`. Switching tabs preserves each branch's stack (inactive branches stay off the URL but in memory). A `StackToConfigCodec` adapter wraps a stack-only codec unchanged if you later add shell URLs.

#### Browser history: `pop` vs `back()`

On the web, each verb maps to a browser-history operation. `push` adds an entry; `replaceTop` / `set` (and the replace half of `pushOrReplaceTop`) **replace** the current entry — matching go_router's `go`. **`pop` adds an entry too**, like a plain `Navigator.pop` and every other Flutter router: it reports the screen it returns to as a new location. That's the standard, least-surprising default — but it means the browser's Back button doesn't track multi-level pops (the popped screen sits one click forward).

When you want the browser Back/Forward buttons to **mirror the app stack across several pops** — typically a custom in-app back button on a web app — reach for **`context.back()`** instead of `context.pop()`:

```dart
// pops the stack and adds a history entry (browser Back won't track it)
onTap: () => context.pop(),

// moves the browser history pointer (a true Back), so browser Back/Forward
// stay in sync with the app stack across multi-level back navigation
onTap: () => context.back(),
```

`context.back()` (and `context.historyGo(int delta)` for multiple steps) does a real `history.go` on the web and lets the inbound URL restore the stack through your codec. It falls back to `pop` off the web, without a codec, or on a cold deep link (no app history behind the current entry), so it's safe to call everywhere. Unlike `pop`, it doesn't deliver a `pushForResult` value — the stack is restored from the URL — so keep `pop` when a screen must return a result.

### 7. Modules

A `RouteModule` packages a feature's routes as a `const`-friendly unit: its own sealed subtype, page builder, optional guards, and optional URL codec. The host mounts it at a top-level route and composes URL routing via `ConfigCodecWithModules`. The module doesn't know what prefix the host will mount it at.

```dart
sealed class CheckoutRoute extends KaiselRoute { const CheckoutRoute(); }
final class CheckoutCart extends CheckoutRoute { const CheckoutCart(); }
final class CheckoutShipping extends CheckoutRoute { const CheckoutShipping(); }
final class CheckoutConfirm extends CheckoutRoute { const CheckoutConfirm(); }

class CheckoutModule extends RouteModule<CheckoutRoute> {
  const CheckoutModule();

  @override
  List<CheckoutRoute> get initialStack => const [CheckoutCart()];

  @override
  Widget buildPage(BuildContext context, CheckoutRoute route) => switch (route) {
    CheckoutCart() => const CheckoutCartScreen(),
    CheckoutShipping() => const CheckoutShippingScreen(),
    CheckoutConfirm() => const CheckoutConfirmScreen(),
  };

  @override
  ModuleStackCodec<CheckoutRoute>? get codec => const CheckoutModuleCodec();
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
    ['confirm'] => const [CheckoutCart(), CheckoutShipping(), CheckoutConfirm()],
    _ => null,
  };
}
```

Mount it from the host's page builder via a marker route in your `AppRoute`:

```dart
final class CheckoutMount extends AppRoute { const CheckoutMount(); }

Widget _buildMainPage(BuildContext context, AppRoute route) => switch (route) {
  CheckoutMount() => const KaiselModuleMount<CheckoutRoute>(
      module: CheckoutModule(),
    ),
  // ... other top-level routes
};
```

Inside the module's screens, `context.router<CheckoutRoute>()` resolves to the module's typed router. Pushing a `CheckoutShipping` typechecks; pushing an `AppRoute` is a compile error. `context.router<AppRoute>()` bypasses the scope and finds the host router above — which is how the module exits itself: `context.router<AppRoute>().pop()` pops `CheckoutMount` off the main stack.

Wire URLs via the composer. The host's main codec stays module-agnostic; the module's codec handles paths under whatever prefix the host declares:

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

A deep link to `/checkout/confirm` restores the full module stack `[Cart, Shipping, Confirm]` so back unwinds through the flow. Adding another module means appending to `modules` — no edits to the main codec.

### 8. Adaptive layouts

Adaptive layouts let one route render a widget that subsumes one or more entries below it on the stack. The canonical use is master-detail at wide breakpoints: the detail route absorbs the master into a single rendered page. The stack stays the same; only the rendering changes.

The builder returns a `KaiselPageResult`: either `KaiselStandalonePage(widget)` (default 1:1) or `KaiselAbsorbingPage(widget, absorbing: n)`, which subsumes `n` entries below it. The widget is yours, so absorption isn't limited to master-detail — `KaiselMasterDetailScaffold` and `KaiselSupportingPaneScaffold` are optional conveniences, and the example app also shows a three-pane layout (`absorbing: 2`), a scaffold-free wizard that collapses into a stepper, and a foldable layout keyed on `MediaQuery.displayFeatures`. Adaptive builders run at three levels — the main delegate, shell branches, and modules — all sharing the same `KaiselPageResult` API and page-identity semantics. Pick the level where the absorbing layout lives.

**At the main delegate:**

```dart
KaiselRouterDelegate<AppRoute>.adaptive(
  router: router,
  builder: (context, route, stack) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return switch ((route, stack.previous, wide)) {
      (ProductDetail(:final id), ProductList(:final category), true) =>
        KaiselAbsorbingPage(
          widget: KaiselMasterDetailScaffold(
            master: ProductListScreen(category: category),
            detail: ProductDetailScreen(id: id),
          ),
        ),
      _ => KaiselStandalonePage(buildSimple(route)),
    };
  },
);
```

**Inside a shell branch** — use `KaiselBranch.adaptive` (heterogeneous branches) or `KaiselShell.adaptive` (homogeneous). The branch's inner navigator goes through the adaptive pipeline; entries within that branch's stack can be absorbed.

```dart
KaiselBranch<HomeRoute>.adaptive(
  router: homeRouter,
  pageBuilder: (context, route, stack) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return switch ((route, stack.previous, wide)) {
      (ProductDetail(:final id), ProductList(), true) => KaiselAbsorbingPage(
        widget: KaiselMasterDetailScaffold(
          master: const ProductListScreen(),
          detail: ProductDetailScreen(id: id),
        ),
      ),
      _ => KaiselStandalonePage(buildSimple(route)),
    };
  },
);
```

**Inside a module** — override `RouteModule.buildAdaptivePage` and set `isAdaptive` to `true`. The default `buildAdaptivePage` wraps `buildPage` as a standalone page, so unmodified modules behave exactly as before.

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
  KaiselPageResult buildAdaptivePage(
    BuildContext context,
    ShopRoute route,
    KaiselStackContext<ShopRoute> stack,
  ) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return switch ((route, stack.previous, wide)) {
      (ShopDetail(:final sku), ShopList(), true) => KaiselAbsorbingPage(
        widget: KaiselMasterDetailScaffold(
          master: const ShopListScreen(),
          detail: ShopDetailScreen(sku: sku),
        ),
      ),
      _ => KaiselStandalonePage(buildPage(context, route)),
    };
  }
}
```

`KaiselStackContext` exposes `stack`, `position`, `previous`, `next`, `isTop`, `isBottom` so the builder can pattern-match on neighbours. `KaiselMasterDetailScaffold` is a small convenience widget laying out master and detail with a divider — replace it with your own chrome if you like.

Two things about page identity under absorption:

- Absorbing pages are keyed by the *lowest* absorbed entry's id, not the absorbing entry's. Going from `[List, DetailA]` to `[List, DetailB]` produces pages with equal keys, so the Navigator doesn't animate — the detail pane just updates (wrap it in an `AnimatedSwitcher` for a fade). Note the transition is `replaceTop`-shaped, not `push`-shaped: `router.push(DetailB)` from `[List, DetailA]` produces three entries and slides in. Use `router.pushOrReplaceTop(DetailB)` so the call pushes when there's no detail on top yet and replaces when there already is.
- The pop target is the top absorbing entry. OS back on `[List, Detail]` absorbed pops `Detail`, leaving `[List]` — back means "undo the last push" regardless of rendering. At the main delegate this needs a `popRoute` override (handled for you) because `Navigator.maybePop` declines when only one page is visible. At the shell-branch and module level, `PopScope` calls `router.pop()` directly, so it's correct by construction.

### 9. Transitions (route-pair-aware)

On the web the default page **fades** — `MaterialPage`'s OS-derived slide feels out of place in a browser; off the web you get the native transition. Change the default with `webTransition:` on `KaiselRouterConfig` / `KaiselRouterDelegate` (`KaiselWebTransition.fade` default, `.none`, or `.platform` to keep the OS transition). A custom `pageWrapper` overrides it entirely.

Customise transitions by passing a `pageWrapper`. The wrapper receives a `KaiselPageWrapperContext<R>` with the route, child, key, and stack context (`position`, `stackLength`, `previous`, `isTop`, `isBottom`). Pattern-match on the route pair to pick a `Page` subclass:

```dart
KaiselRouterDelegate<AppRoute>(
  router: router,
  builder: (context, route) => switch (route) { /* ... */ },
  pageWrapper: (ctx) => switch ((ctx.previous, ctx.route)) {
    (ProductList(), ProductDetail()) =>
      _ZoomPage(key: ctx.key, child: ctx.child),
    (_, Settings()) =>
      _SlideUpPage(key: ctx.key, child: ctx.child),
    _ => MaterialPage<Object?>(key: ctx.key, child: ctx.child),
  },
);
```

The Navigator handles push/pop direction automatically (forward on add, reverse on remove). The wrapper's job is choosing the *style* of transition; the framework chooses the direction. `previous` refers to the page below in the *rendered* stack — for absorbing pages, the absorbed entries don't show up as `previous`.

Shared-element transitions work via Flutter's `Hero` widget against the per-Navigator `HeroController` the framework already installs. Tag widgets with `Hero(tag: ...)` and they animate across pushes — no new API.

### 10. Page scope for descendants

The framework wraps every rendered page's child in a `KaiselPageScope` `InheritedWidget`. Deeply-nested widgets read it via `KaiselPageScope.maybeOf(context)` (or `.of(context)` when always in a kaisel page). It exposes the same fields as the wrapper context — `route`, `position`, `stackLength`, `previous`, `isTop`, `isBottom` — but to the page's content, not just the wrapping layer.

```dart
class BookDetailScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Narrow: rendered stack is [List, Detail], isBottom false → show back arrow.
    // Wide: Detail absorbs List, rendered stack is [Detail], isBottom true → hide it.
    final isOnly = KaiselPageScope.maybeOf(context)?.isBottom ?? false;
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: !isOnly),
      // ...
    );
  }
}
```

Useful for hiding back arrows on absorbing master-detail pages, "back to X" labels using the route below, AppBar chrome that animates on `isTop`, or pattern-matching on `scope.route` from a deeply-nested widget.

A user-supplied `pageWrapper` receives `ctx.child` already wrapped in the scope, so `Page(child: ctx.child)` propagates it automatically. A wrapper that builds a Page with a *different* child is responsible for re-wrapping in `KaiselPageScope` itself if it wants descendants to see it.

### 11. Navigation observers (analytics)

Attach `NavigatorObserver`s — analytics, Sentry, `RouteObserver` — with an `observers:` **builder** on `KaiselRouterConfig` (or `KaiselRouterDelegate`):

```dart
KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  observers: () => [MyAnalyticsObserver()],
  builder: (context, route) => switch (route) { /* … */ },
);
```

You pass it **once**, on the config — kaisel then attaches observers to **every** navigator it manages: the main stack *and* each shell branch, module, and active flow. You don't wire shells (or modules or flows) separately, and you don't miss their events.

**Every navigation. One observer. Zero wiring.** That includes the navigations the `Navigator` itself never reports: a shell **tab switch** (only the branch container's index moves) and **adaptive in-place changes** (a wide-width master-detail push, swap, or pop updates one absorbed page). kaisel reports them to your observers **kind-matched** — absorbed growth as a `didPush`, absorbed shrink as a `didPop`, swaps and tab switches as a `didReplace` — carrying the usual `routeName` / `arguments`, with push/pop pairing the same route instance. A stock `FirebaseAnalyticsObserver` logs uniformly at every width, with no double events at narrow widths and nothing on a resize.

It's a builder (`List<NavigatorObserver> Function()`), not a list, on purpose: a `NavigatorObserver` instance belongs to a **single** `Navigator`, and kaisel has many — exactly those listed above. kaisel calls the builder **once per navigator**, so each gets its **own fresh instance** (cached, so it isn't rebuilt every frame). Return new instances each call; don't hand back a shared one — that's the only catch.

Because each navigator has its own observer, a bottom-nav app gets one observer per tab — each logging that tab's routes, plus the switches between them. If you'd rather react to changes with the old and new stacks as **values**, use `onTransition` — on the config for the main stack, or on any `KaiselRouter` you construct yourself (e.g. shell branches):

```dart
onTransition: (from, to) {
  if (to.last != from.last) {
    analytics.logScreenView(screenName: to.last.routeName);
  }
},
```

**Route names.** Off-the-shelf observers (e.g. `FirebaseAnalyticsObserver`) read `route.settings.name`. kaisel sets it from each route's `routeName` getter — which defaults to the route's runtime type (`'ProductDetail'`) — and puts the route itself in `settings.arguments`. Override `routeName` for a custom screen name (it's `routeName`, not `name`, so it never clashes with a domain field your route carries):

```dart
final class ProductDetail extends AppRoute {
  const ProductDetail(this.id);
  final String id;
  @override
  String get routeName => 'product_detail';
}
```

> **Obfuscation caveat.** The default `routeName` is `runtimeType.toString()`, which is **minified** in release builds compiled with `--obfuscate` (`ProductDetail` → `a`). For stable analytics names in obfuscated builds, override `routeName` with a string literal as above — string literals aren't obfuscated.

### 12. State restoration

Survive an OS process-kill (iOS background-kill, Android low-memory) and relaunch where the user left off. Turn it on with `restorationScopeId` on your `MaterialApp`:

```dart
MaterialApp.router(routerConfig: _config, restorationScopeId: 'app');
```

**Stack restoration — URL/codec apps.** If you pass a `codec`, the main stack (plus shell/module state your codec encodes) restores through Flutter's `Router` for free — the app `restorationScopeId` above is all you need. The codec is just a serializer: on mobile its `Uri` is internal, never shown.

**Within-page state** (scroll offset, text fields via `RestorationMixin`). Give the navigators a restoration scope and the pages an id:

```dart
KaiselRouterConfig<AppRoute>(
  restorationScopeId: 'main',   // scopes the main navigator
  builder: ...,                 // shell branches + modules get their own scope automatically
);
```

The page id comes from `KaiselRoute.restorationId`, which defaults to `routeName` for parameterless routes and `null` for parameterized ones (they'd share a bucket). Opt a parameterized route in with a param-aware id:

```dart
final class ProductDetail extends AppRoute {
  const ProductDetail(this.id);
  final String id;
  @override
  String get restorationId => 'product-$id';
}
```

**No codec? Restore the stack anyway.** Apps without URLs can restore the **main** stack with a small rebuild function — no codec needed. kaisel saves each route's `routeName` + `props`; you map them back:

```dart
KaiselRouterConfig<AppRoute>(
  restoreRoute: (name, props) => switch (name) {
    'ProductDetail' => ProductDetail(props[0] as String),
    _               => const Home(),
  },
  builder: ...,
);
```

It's deserialize-only (kaisel auto-serializes), and `props` must be JSON-encodable. Under `--obfuscate`, override `routeName` so the saved name matches your switch (a debug warning fires if it doesn't). Nested shell/module state still needs a codec.

## Why no equality codegen

Routing libraries that bake in `freezed` force codegen on every consumer. `kaisel` provides default `props`-based equality on `KaiselRoute` itself, so the common case is a one-line override. Prefer `freezed sealed`? That still works. Prefer `Equatable`? Declare your routes with `extends KaiselRoute with EquatableMixin`. The library doesn't impose a choice — your override always wins.

## Migrating

Coming from another router? See the migration guides in [`doc/migration/`](doc/migration/):

- [From go_router](doc/migration/from-go-router.md)
- [From auto_route](doc/migration/from-auto-route.md)
- [From Navigator (imperative or named routes)](doc/migration/from-navigator.md)

## Lints

[`kaisel_lint`](https://github.com/Mastersam07/kaisel/tree/main/packages/kaisel_lint) is an analyzer plugin with kaisel-aware rules, quick fixes, and assists — e.g. a `KaiselRoute` with fields but no `props` override, or a `KaiselModalRoute` pushed onto the main stack instead of opened with `run<T>`.

Lints are always opt-in in Dart (a dependency can't enable them for you), so add the plugin and turn it on:

```yaml
# pubspec.yaml
dev_dependencies:
  kaisel_lint: ^0.5.0
```

```yaml
# analysis_options.yaml
include: package:kaisel_lint/recommended.yaml
```

That activates the plugin with its correctness baseline on — `require_route_props` and `avoid_modal_route_on_main_stack`. To opt into the stylistic/adaptive rules or tune severities, write the activation yourself instead of including the file:

```yaml
# analysis_options.yaml
plugins:
  kaisel_lint:
    version: ^0.5.0
    diagnostics:
      require_route_props: true
      avoid_modal_route_on_main_stack: true
      prefer_const_route_constructors: true   # opt-in
```

Restart the analysis server after editing. See the [`kaisel_lint` README](https://github.com/Mastersam07/kaisel/tree/main/packages/kaisel_lint) for the full rule list and the fixes/assists each ships.

## Editor / AI assistance

An [agent skill](https://github.com/Mastersam07/kaisel/tree/main/skills/kaisel) teaches AI coding agents (Claude Code, Cursor, opencode, …) how kaisel works, so they generate idiomatic kaisel code instead of guessing. Install it with the [`skills` CLI](https://github.com/vercel-labs/skills):

```sh
npx skills add Mastersam07/kaisel
```

## Status

**v1.0.0-dev.5, a 1.0 pre-release.** The core surface is in place: routes, guards, shells (homogeneous and per-branch typed), typed main-stack results (`pushForResult<T>`), modal flows (rendered as routes on the main navigator, so dialogs and observers compose with them), URL-addressable shell and module state, composable modules with URL composition, adaptive layouts at every level, route-pair-aware transitions, `KaiselPageScope`, navigator observers, a DevTools extension, state restoration, and opt-in Android predictive-back transitions. The public API is shaped for stability but not yet frozen — expect occasional breaking changes before 1.0, each with a migration note in the [changelog](CHANGELOG.md).

## Example

The [`example/`](example/) app has several entry points, each demonstrating one slice of the library (branched shells, modal flows, modules, adaptive layouts, transitions). See [`example/README.md`](example/README.md) for how to run each.

## License

[Apache-2.0](LICENSE) © 2026 Codefarmer.
