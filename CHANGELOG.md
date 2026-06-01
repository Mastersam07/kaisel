# Changelog

## 0.12.0: Page scope for descendants

A small additive release: framework-provided
`GatePageScope` `InheritedWidget` exposes the wrapper context to
descendant widgets. v0.11 gave the page-wrapping layer enough info
to choose transitions; v0.12 gives the descendant widgets enough
info to make context-aware decisions ("am I the only rendered
page?", "what's the route below me?").

### API

- **`GatePageScope`**: new `InheritedWidget` in
  `src/gate_page_scope.dart`. Exposes `route` (typed as
  `GateRoute`), `position`, `stackLength`, `previous`, and the
  convenience getters `isTop` / `isBottom`. Read with
  `GatePageScope.maybeOf(context)` (returns null if outside a
  gate page) or `GatePageScope.of(context)` (asserts there is
  one).

- The framework injects `GatePageScope` at every wrap call site:
  the main delegate's simple and adaptive paths, and the inner
  navigator's simple and adaptive paths. User-supplied
  `pageWrapper` callbacks receive `ctx.child` already wrapped in
  the scope, so a wrapper that does
  `Page(child: ctx.child)` automatically propagates it into the
  page's content tree.

### Why this matters

The canonical use case is hiding a back arrow on a page that's the
only one rendered. With absorbing master-detail layouts, the
router's stack has multiple entries but the rendered Navigator
shows just one page. Before v0.12, the detail screen needed an
app-side `InheritedWidget` (the example app called it
`AdaptiveContext`) injected at the absorbing-builder site to know
"don't render a back arrow, I'm absorbing the page below". With
v0.12 the detail screen reads
`GatePageScope.maybeOf(context)?.isBottom` directly. The example's
`AdaptiveContext` is gone.

The same pattern applies to "back to X" labels (read
`scope.previous`), AppBar fading per `isTop`, and route-aware
deep-nested widgets that don't want to thread the route through
constructors.

### Example

`example/lib/main_adaptive.dart` no longer ships its own
`AdaptiveContext` class. `BookDetailScreen` reads
`GatePageScope.maybeOf(context)?.isBottom` instead. The behaviour
is identical: at narrow widths the rendered stack is
`[BookList, BookDetail]` and `isBottom == false` so the back arrow
shows; at wide widths the BookDetail page absorbs BookList, the
rendered stack is `[BookDetail]` only, `isBottom == true` so the
back arrow hides.

### Caveat

A custom `pageWrapper` that constructs a Page with a different
child (replacing `ctx.child` entirely instead of passing it
through) is responsible for re-wrapping in `GatePageScope` if it
wants descendants to see it. The common pattern of
`Page(child: ctx.child)` just works.

---

## 0.11.0: Direction-aware transitions and adaptive ergonomics

Two changes. The headline is the breaking-but-deferred wrapper
signature change that unblocks direction-aware transitions. The
follow-up is the adaptive demo's exposed papercut.

### Direction-aware transitions

The `GatePageWrapper` typedef has changed signature. Previously it
took three positional arguments `(R route, Widget child, LocalKey
key)`. It now takes a single `GatePageWrapperContext<R>` with the
same three fields plus stack context: `position`, `stackLength`,
and `previous` (the route below this page in the rendered stack,
null at the bottom). The wrapper pattern-matches on the route pair
to pick transitions that care where you came from:

```dart
pageWrapper: (ctx) {
  return switch ((ctx.previous, ctx.route)) {
    (ProductList(), ProductDetail()) =>
      _ZoomPage(key: ctx.key, child: ctx.child),
    (_, Settings()) =>
      _SlideUpPage(key: ctx.key, child: ctx.child),
    _ => MaterialPage(key: ctx.key, child: ctx.child),
  };
}
```

The Navigator still handles push/pop direction automatically based
on pages-list diff. The wrapper's job is choosing the *style* of
transition (which [Page] subclass to construct); the framework
chooses the direction (forward on add, reverse on remove).

`GatePageWrapperContext` lives in `src/gate_page_wrapper.dart`,
exported from the barrel.

For absorbing pages, `previous` refers to the page below in the
**rendered** stack, not the router's full stack. If page B at
rendered position 1 absorbs entries below it, the page at
rendered position 2 sees `previous == B.route`, not the absorbed
entries below B.

**Shared elements** work via Flutter's `Hero` widget on top of the
per-Navigator `HeroController` the framework already installs.
There's no new framework API for them; tag widgets with `Hero(tag:
...)` and they animate across pushes.

### Adaptive ergonomics

- **`GateRouter.pushOrReplaceTop(R route, {bool Function(R)? when})`**:
  pushes [route] if [when] returns false for the current top,
  replaces the top otherwise. Defaults to "replace if the current
  top has the same runtime type as [route]", which is correct for
  the common sealed-route master-detail case. Pass an explicit
  predicate for finer control, or `(_) => false` to force a push.

  ```dart
  // In the master pane's list tile:
  onTap: () => context
      .router<BookRoute>()
      .pushOrReplaceTop(BookDetail(book.id)),
  ```

  Pushes when the current top is `BookList` (becoming
  `[BookList, BookDetail(id)]`); replaces when the current top is
  already a `BookDetail` (`[BookList, BookDetail(other)]` →
  `[BookList, BookDetail(id)]`). The latter keeps the stack at
  depth 2 and the absorbing-pipeline page identity stable, so the
  detail pane updates in place without a Navigator slide.

- **`GateRouter.replace` renamed to `GateRouter.replaceTop`**. The
  method has always only touched the top entry; the longer name
  makes that immediate at the call site.

### Example

The adaptive demo uses `pushOrReplaceTop` in its `_selectBook`
helper. Run with `flutter run -t lib/main_adaptive.dart` from the
example directory.

---

## 0.10.0: Nested modal flows

v0.3 introduced `router.run<T>(...)` for typed modal sub-flows but
restricted to one flow at a time. A second `run` call threw a
`StateError`. v0.10 reshapes the API around a stack of flows: nested
runs push onto the stack, completions pop LIFO, and the delegate
renders one modal layer per active flow. A payment flow can itself
`run` an "add card" sub-flow; an auth flow can open a "verify
identity" sub-flow.

### API

- **`GateActiveFlow<R>`**: a read-only view of one entry in the
  active flow stack. Exposes the flow's defining route and its
  sub-router. The completer is private so callers can't bypass the
  LIFO completion discipline.

- **`GateRouter.activeFlows`**: returns `List<GateActiveFlow<R>>`,
  ordered oldest-first (bottom of the modal stack to topmost). The
  delegate renders one overlay layer per entry. The last entry is
  the flow that `completeFlow` and `dismissFlow` resolve.

- **`GateRouter.hasActiveFlow`**: convenience for
  `activeFlows.isNotEmpty`. Unchanged from v0.3.

- **`GateRouter.run<T>`**: no longer throws when a flow is active.
  Appends to the stack.

- **`GateRouter.completeFlow<T>(value)`** and **`dismissFlow()`**:
  resolve the topmost flow. Only the topmost can be completed via
  this API. To unwind multiple flows, complete the topmost, await
  it, then complete the next.

- **Removed**: the v0.3 `activeFlowRoute` and `activeFlowRouter`
  singleton accessors. Use `activeFlows.last.route` and
  `activeFlows.last.router` (or `lastOrNull` for a null-safe form).

### Delegate

`GateRouterDelegate.build` renders one modal overlay layer per
active flow. Each layer has its own `GateInnerNavigator` (with a
stable per-flow `GlobalKey`), its own `RouterScope<R>`, its own
`FlowScope`, and its own `PopScope`. The topmost layer ends up
deepest in the widget tree, so its `PopScope` sees Android back
gestures first.

The private `_ModalOverlay` widget that v0.3 used for the single-
flow case has been removed; its responsibilities are inlined into a
`_buildFlowLayer` method on the delegate.

`GateRouter.dispose` resolves every pending flow with `null`.

### Pop semantics with nested flows

Each flow layer's `PopScope` works the same as the v0.3 single-flow
case: `canPop: false` (the layer intercepts back), and the handler
pops within the flow if possible, else dismisses the flow. With
nested flows, the topmost layer's PopScope handles back first; when
it dismisses, the layer below resumes control. Pop unwinds one flow
at a time.

### Example app

A second entry point demonstrates the adaptive pipeline:
`example/lib/main_adaptive.dart`. A book catalogue with master-detail
behaviour at wide widths; the route stack stays the same while the
rendering switches between absorbed and stacked layouts as you
resize. Run with `flutter run -t lib/main_adaptive.dart` from the
example directory. See `example/README.md`.

---

## 0.9.0: Adaptive layouts inside shells and modules

The v0.8 release shipped adaptive layouts at the main `GateRouterDelegate`,
which is the wrong level for the most common use case. Master-detail
almost always lives inside a shell tab (a "products" tab whose list
and detail collapse at wide widths) or inside a feature module (a
checkout flow's review/summary side-by-side at wide widths). v0.9
plumbs the adaptive pipeline through the inner navigator shared by
`GateBranch`, `GateShell`, and `GateModuleMount`, so any of them
can render absorbing pages.

Additive: v0.8 code still compiles and runs unchanged.

### Added

- **`GateBranch.adaptive`**: new named constructor on `GateBranch`.
  Takes a `GateAdaptivePageBuilder<R>` instead of a
  `GatePageBuilder<R>`. The branch's inner navigator goes through
  the adaptive pipeline.

  ```dart
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
  );
  ```

- **`GateShell.adaptive`**: new named constructor on `GateShell`
  (homogeneous shell). All branches share the adaptive builder
  (they share the route type). For per-branch adaptive
  configuration use `GateBranchedShell` with `GateBranch.adaptive`.

- **`RouteModule.buildAdaptivePage`**: new virtual method on
  `RouteModule` that returns a `GatePageResult`. Default
  implementation wraps `buildPage` as `GateStandalonePage(...)`, so
  existing modules are unaffected. Adaptive modules override this
  and opt in by setting `isAdaptive` to `true`.

  ```dart
  class ShopModule extends RouteModule<ShopRoute> {
    const ShopModule();

    @override
    bool get isAdaptive => true;

    @override
    Widget buildPage(BuildContext context, ShopRoute route) =>
      switch (route) { /* ... */ };

    @override
    GatePageResult buildAdaptivePage(
      BuildContext context,
      ShopRoute route,
      GateStackContext<ShopRoute> stack,
    ) {
      final wide = MediaQuery.sizeOf(context).width >= 700;
      return switch ((route, stack.previous, wide)) {
        (ProductDetail(:final id), ProductList(), true) =>
          GateAbsorbingPage(
            widget: GateMasterDetailScaffold(
              master: const ProductListScreen(),
              detail: ProductDetailScreen(id: id),
            ),
          ),
        _ => GateStandalonePage(buildPage(context, route)),
      };
    }
  }
  ```

- **`RouteModule.isAdaptive`**: opt-in flag (default `false`).
  Dart doesn't give us reliable runtime override detection, so
  modules signal intent explicitly. Setting `isAdaptive` to true
  without overriding `buildAdaptivePage` still works (the default
  returns a standalone page); the difference is the navigator goes
  through the adaptive pipeline.

- **`GateInnerNavigator.adaptivePageBuilder`**: new optional
  parameter on the inner-navigator widget that shells and modules
  embed. Mutually exclusive with `pageBuilder`; one of the two
  must be provided. Custom hosts (your own composite widget that
  embeds a router) can pass either, same as the built-in ones.

### Changed

- `GateBranch.pageBuilder` and `GateShell.pageBuilder` are now
  private (`_pageBuilder`). They were public final fields in v0.8.
  No external code in the package or example reads them. If your
  app introspected the field, switch to constructing through the
  named constructors as before.
- The adaptive page-key type, `GateAdaptiveKey`, and the shared
  iteration helper `buildAdaptivePages` have moved from the
  delegate's file into `gate_adaptive.dart`. They aren't part of
  the public barrel. Listed here only because some internals
  reading code might notice the file location change.

### Pop semantics inside shells and modules

Shells and modules use `PopScope` + `router.pop()` directly to
handle the Android back gesture. They don't go through the
mixin's `popRoute` → `Navigator.maybePop` path that bit the main
delegate in v0.8. The PopScope's `canPop` reads `router.canPop`,
which reflects the logical stack regardless of how many visible
pages absorption produced. So absorbing inside a shell branch or
module is correctly back-poppable by construction. No
`popRoute`-style override was needed at this level.

### Scope

- `GateShell.adaptive` is homogeneous: all branches share the
  adaptive builder, matching the homogeneous `GateShell` model.
  Per-branch adaptive configuration goes through `GateBranchedShell`
  + `GateBranch.adaptive`.
- The adaptive iteration is identical at the main delegate, shell
  branch, and module mount levels — same `buildAdaptivePages`
  helper, same `GateAdaptiveKey` semantics. A `GateAbsorbingPage`
  inside a shell branch absorbs entries within that branch's
  stack, not across the host stack.

---

## 0.8.0: Adaptive layouts

The headline is `GateRouterDelegate.adaptive`, a new constructor that
takes a stack-aware page builder. Adaptive page builders can decide
to render an *absorbing* page that collapses one or more entries
below it on the stack into a single rendered page. The canonical
use is master-detail at wide breakpoints: the detail route absorbs
the master into one widget rather than appearing on top of it.

Additive: v0.7 code still compiles and runs unchanged.

### Added

- **`GateRouterDelegate.adaptive`**: new named constructor. Takes a
  `GateAdaptivePageBuilder` instead of a `GatePageBuilder`. The
  main stack goes through the adaptive pipeline. Modal flows
  continue to render through the simple per-route path; if you use
  an adaptive delegate with `router.run<T>(...)`, the modal builder
  synthesises a simple builder from your adaptive one (calling it
  with a single-entry stack context and using the resulting
  widget; the `absorbing` count is ignored on the modal path).

  ```dart
  GateRouterDelegate<AppRoute>.adaptive(
    router: router,
    builder: (context, route, stack) {
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
  );
  ```

- **`GatePageResult`**: sealed result type returned by an adaptive
  builder. Two variants: `GateStandalonePage(widget)` for the
  default 1:1 stack-to-pages case, `GateAbsorbingPage(widget,
  absorbing: n)` to render a widget that subsumes `n` entries
  below.

- **`GateStackContext<R>`**: passed to the adaptive builder for
  each entry. Surfaces `stack`, `position`, `previous`, `next`,
  `isTop`, `isBottom`. Pattern-match on neighbours to decide what
  to render.

- **`GateAdaptivePageBuilder<R>`**: typedef for
  `GatePageResult Function(BuildContext, R, GateStackContext<R>)`.

- **`GateMasterDetailScaffold`**: small convenience widget. Rows a
  master and detail with an optional divider; takes a
  `masterFraction` for the split. Useful inside an absorbing
  page's widget. Replace with your own layout if you need
  different chrome.

### Page identity under absorption

The page produced by `GateAbsorbingPage` is keyed by the *lowest*
absorbed entry's id, not the absorbing entry's. This matters for
two scenarios:

1. **Selecting a different detail in master-detail.** Going from
   `[List, DetailA]` to `[List, DetailB]` produces pages with
   equal keys (both keyed by List's id). The Navigator sees the
   same page identity; only the child widget content changes. No
   slide-in transition; the detail pane just updates. If you want
   a fade between details, wrap the swapping content in an
   `AnimatedSwitcher`.

2. **Toggling absorbed vs standalone.** When the breakpoint
   changes and `[List, Detail]` flips from absorbed (one page) to
   non-absorbed (two pages), the master page's identity is
   preserved (still keyed by List's id). The detail page either
   appears on top (narrow) or vanishes into the absorbing widget
   (wide).

The pop target is the top absorbing entry, not the lowest absorbed
one. An OS back gesture on `[List, Detail]` absorbed pops Detail,
leaving `[List]`. This is what users expect: back means "undo the
last push" regardless of how the stack happens to be visually
rendered.

There's one wrinkle here. When absorption collapses everything to
a single visible page, Flutter's `Navigator.maybePop` returns false
because there's no route below the current one. In v0.8,
[GateRouterDelegate.popRoute] tries the Navigator first and falls
through to `router.pop()` when it detects the absorbing state
(visible page count below the logical entry count). Without this,
the OS back gesture on a single-page absorbing state would bubble
out of the app instead of unwinding the logical stack. The simple
(non-adaptive) pipeline still uses the mixin's `popRoute` unchanged.

### Scope and limitations

- Adaptive is currently available at the main `GateRouterDelegate`
  only. Per-branch typed shells (`GateBranchedShell`) and modules
  (`RouteModule`) still use the simple per-route builder. Adding
  adaptive support to nested routers is tracked for v0.9+.
- The simple `GatePageBuilder` is still the default. The base
  `GateRouterDelegate(...)` constructor is unchanged.
- A user-supplied `pageWrapper` works with adaptive pages but
  doesn't get any signal that a page is absorbing. The wrapper
  sees the absorbing entry's route and the absorbed entry's key.
  If you need to know inside your wrapper, switch to standalone
  pages or contribute a `pageWrapper` API extension in v0.9.

---

## 0.7.0: Module URL composition

One headline feature, additive. Modules can now ship their own URL
codec; the host composes URL routing without duplicating each
module's URL structure in its main codec.

### Added

- **`ModuleStackCodec<R>`**: codec for a module's URL structure,
  relative to whatever prefix the host mounts it at. Module authors
  subclass this to make their module URL-addressable. The host stays
  unaware of the module's internal route types.

  ```dart
  class CheckoutModuleCodec extends ModuleStackCodec<CheckoutRoute> {
    const CheckoutModuleCodec();

    @override
    List<String> encode(List<CheckoutRoute> stack) => switch (stack.last) {
      CheckoutCart() => const [],
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

  Conventions: `encode` of the module's root state returns
  `const []` (the mount prefix is enough); `decode` of `const []`
  returns the module's root stack; `decode` returns `null` for
  unrecognised segments.

- **`UntypedModuleStackCodec`**: the type-erased view of
  `ModuleStackCodec`. Used by the composer so a single
  `List<ModuleMount>` can hold codecs for modules with different
  internal route types. Most app code references the typed
  `ModuleStackCodec<R>` subclass instead.

- **`ModuleMount<HostR>`**: a mount declaration with the host's marker
  route, the URL prefix the module answers to, and the module's
  URL codec. Used inside `ConfigCodecWithModules.modules` to wire
  URL routing across module boundaries.

- **`ConfigCodecWithModules<R>`**: a `GateConfigCodec` that
  composes a base codec with one or more module mounts. URLs under
  a mount's prefix go through the module's codec; everything else
  delegates to the base codec.

  ```dart
  const appCodec = ConfigCodecWithModules<AppRoute>(
    baseCodec: _MainAppCodec(),
    modules: [
      ModuleMount(
        mountRoute: CheckoutMount(),
        prefix: '/checkout',
        codec: _CheckoutModuleCodec(),
      ),
    ],
  );
  ```

  The host's main codec stops knowing about `/checkout/*` URLs;
  the module ships that itself. Adding more modules means
  appending to `modules`, not editing the main codec.

- **`RouteModule.codec`**: new optional getter on `RouteModule`.
  Returns the module's `ModuleStackCodec<R>` if the module is
  URL-aware, `null` otherwise. The composer reads it via
  `ModuleMount.codec` (passed separately so the mount can also
  declare its prefix, which is the host's decision).

### Compatibility

Purely additive. v0.6 codecs that hand-roll `/module-prefix/*` URLs
in their main codec keep working unchanged; the new composer is an
opt-in convenience. Mixing approaches in one app is fine; the
composer is just a `GateConfigCodec` like any other.

### Decode semantics

- A URL under a mount's prefix is given to the module's codec. If
  the module codec returns `null`, the composer returns `null`
  and does NOT fall through to the base codec. The URL clearly
  belongs to that module's namespace.
- A URL with no matching mount prefix is given to the base codec.
- `modules` is searched in order. List longer prefixes first if
  you have nested-prefix collisions (`/checkout/v2` before
  `/checkout`).

---

## 0.6.0 — Composable `RouteModule`s + unified nested-router state

One headline feature, one structural cleanup. **Breaking changes
from v0.5** — the configuration's nested-state field changed shape.

### Added

- **`RouteModule<R>`** — a `const`-friendly base class that
  packages a feature's routes into a reusable unit. A module
  declares its own sealed subtype `R`, its `initialStack`, a
  `buildPage(context, route)` resolver, optional `guards`, and an
  optional `pageWrapper`. Pattern-matches the same way the host's
  main router does, with the same compile-time exhaustiveness.

  ```dart
  sealed class CheckoutRoute extends GateRoute { const CheckoutRoute(); }
  final class CheckoutCart extends CheckoutRoute { const CheckoutCart(); }
  final class CheckoutShipping extends CheckoutRoute {
    const CheckoutShipping();
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
        };
  }
  ```

- **`GateModuleMount<R>`** — the widget that mounts a `RouteModule`.
  Creates the module's typed `GateRouter<R>` internally, owns its
  lifecycle, installs a `RouterScope<R>` so descendants find the
  module's router via `context.router<R>()`. The host's main router
  is still reachable via `context.router<AppRoute>()` — same
  lookup-by-exact-type semantics as `GateBranch`.

  ```dart
  Widget _buildMainPage(BuildContext context, AppRoute route) =>
      switch (route) {
        CheckoutMount() => const GateModuleMount<CheckoutRoute>(
            module: CheckoutModule(),
          ),
        // ... other top-level routes
      };
  ```

- **`GateModuleConfig`** — captures a mounted module's internal
  stack so the URL can include it. Sibling to `GateShellConfig`
  under the new sealed `GateNestedConfig` base type.

### Changed (breaking)

- **`GateConfig.shellState` is gone. `GateConfig.nestedState` takes
  its place.** The configuration now carries a single sealed
  `GateNestedConfig?` — either a `GateShellConfig` or a
  `GateModuleConfig`. The "at most one nested kind on top of the
  main stack" property is enforced by the type system, not a
  runtime assertion. Pattern-match in your codec:

  ```dart
  // before (v0.5)
  Uri encode(GateConfig<AppRoute> config) {
    final shell = config.shellState;
    return shell != null
        ? _encodeShell(shell)
        : _encodeFlat(config.mainStack.last);
  }

  // after (v0.6)
  Uri encode(GateConfig<AppRoute> config) =>
      switch ((config.mainStack.last, config.nestedState)) {
        (MainShell(), final GateShellConfig shell)   => _encodeShell(shell),
        (CheckoutMount(), final GateModuleConfig m)  => _encodeCheckout(m),
        (Splash(), _)                                 => Uri(path: '/'),
        // ...
      };
  ```

  Codecs need a one-pass migration; rename `shellState` →
  `nestedState` and dispatch by config kind in `encode`. `decode`
  changes are mechanical (`shellState:` → `nestedState:`).

- **Host machinery unified.** The internal interfaces
  `GateShellHost` + `GateShellRestoreHandle` + `GateShellHostScope`
  collapse to `GateNestedHost` + `GateNestedHandle` +
  `GateNestedHostScope`. The delegate now keeps a single LIFO list
  of registered handles — the most recently registered is the
  active one — instead of a dedicated slot per nested kind. These
  types weren't exported from `package:gate/gate.dart`, so the
  rename is only visible to authors building custom nested routers.

- **Handles declare their config kind via `Type get configType`.**
  The delegate uses it to match pending state (from a cold-start
  deep link) to the right registered handle.

### Why the cleanup

The two-slot model (`shellState`, `moduleState`) was an additive
choice that preserved v0.5 source compatibility. With no users in
the wild yet, that compatibility wasn't worth the structural cost:
two parallel host interfaces, two parallel scope widgets, a runtime
assertion duplicating what the type system can express. The sealed
`GateNestedConfig` says "at most one nested router rides the URL"
at the type level, which is what we mean.

### Why modules

The v0.5 article framed Dart 3-native routing as enabling
"feature-team plug-and-play": a feature ships with its own sealed
subtype, its own pageBuilder, its own guards, and the host composes
it. v0.5 didn't have that yet — every route had to live in the
host's `AppRoute`. v0.6 closes that gap. A payments SDK, a KYC
flow, an embedded checkout — all can ship as a `RouteModule` the
host mounts at a top-level route, with deep-linkable URLs.

---

## 0.5.0 — Per-branch URLs reaching into shell stacks

One headline feature, one breaking change (with a one-line migration).

### Added

- **`GateConfig<R>`** and **`GateShellConfig`** — the new
  configuration types that flow between the URL bar and the router.
  The configuration now describes both the main router's stack and
  (when a branched shell is mounted) the active branch's stack:

  ```dart
  GateConfig<AppRoute>(
    mainStack: [MainShell()],
    shellState: GateShellConfig(
      activeBranch: 0,
      activeBranchStack: [HomeRoot(), ProductDetail('sku-42')],
    ),
  )
  ```

  Encodes to `/home/products/sku-42` and round-trips back on deep
  link. Only the active branch's stack rides the URL — inactive
  branches keep their in-memory history so switching tabs and back
  doesn't reset them.

- **`GateConfigCodec<R>`** — codec interface for the richer
  configuration. Pattern-match on the main stack's top and the shell
  state to produce URLs; pattern-match on URI path segments to
  decode. The example shows the full pattern.

- **`StackToConfigCodec<R>`** — adapter that wraps a v0.4
  [GateStackCodec] so existing stack-only codecs work unchanged. Use
  it via `GateRouteInformationParser.fromStackCodec(...)` — that's
  the entire v0.4 → v0.5 migration if you don't need shell URLs.

- **`GateNavigator.stack` and `GateNavigator.restoreStack`** — the
  non-generic shell-friendly interface gains read/restore methods so
  `BranchedShellRouter` can capture and replay branch state across
  heterogeneously typed routers. `restoreStack` validates each route
  is assignable to the router's `R` at runtime; mismatches throw
  `ArgumentError` before any state mutates.

- **`BranchedShellRouter.captureConfig()` and `.restoreFromConfig(...)`**
  — bridge between the shell's runtime state and the URL. `restoreFromConfig`
  updates only the target branch and leaves inactive branches alone.

- **Shell-host registration via inherited widget** — a mounted
  `GateBranchedShell` discovers the enclosing `GateRouterDelegate`
  through `GateShellHostScope` and registers itself for URL
  capture/restore. Cold-start deep links into the shell are
  supported via a pending-state queue: if the URL arrives before
  the shell mounts, the delegate stores it and applies it when the
  shell registers.

### Changed (breaking)

- **`GateRouterDelegate<R>`** is now `RouterDelegate<GateConfig<R>>`
  instead of `RouterDelegate<List<R>>`, and **`GateRouteInformationParser<R>`**
  is parameterised the same way.

  **If you have a custom delegate or parser**, migrate the
  configuration type.

  **If you use the gate-provided ones with a `GateStackCodec`** (the
  v0.4 default), change one line at the wiring site:

  ```dart
  // v0.4
  GateRouteInformationParser<AppRoute>(
    codec: const AppStackCodec(),
    fallback: const [Splash()],
  )

  // v0.5 — same codec, minimal migration
  GateRouteInformationParser<AppRoute>.fromStackCodec(
    codec: const AppStackCodec(),
    fallback: const [Splash()],
  )
  ```

  To start using shell URLs, replace your `GateStackCodec` with a
  `GateConfigCodec` and pass it via the regular constructor.

## 0.4.0 — Per-branch typed routes in shells

One additive feature. No breaking changes.

### Added

- **`GateBranchedShell`, `GateBranch<R>`, `BranchedShellRouter`** — a
  shell whose branches have **different** sealed route types. Where
  the v0.2/v0.3 `GateShell<R>` requires every branch to share one
  route type (so pushing `DiscoverRoute` into the Home tab is a
  runtime concern), the branched shell typeschecks each branch
  independently:

  ```dart
  sealed class HomeRoute extends GateRoute { const HomeRoute(); }
  sealed class DiscoverRoute extends GateRoute { const DiscoverRoute(); }

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
        pageBuilder: (context, route) => switch (route) {
          DiscoverRoot() => const DiscoverScreen(),
          FeedItem(:final id) => FeedItemScreen(id: id),
        },
      ),
    ],
    chromeBuilder: ...,
  )
  ```

  Inside a branch screen, `context.router<HomeRoute>()` returns the
  home branch's typed router; trying to push a `DiscoverRoute` into
  it is a compile error. `context.router<AppRoute>()` still returns
  the main app router, because `RouterScope` lookup is by exact
  generic type — different `R`s don't shadow each other.

- **`GateNavigator`** — non-generic interface that `GateRouter`
  implements, exposing `canPop` and `pop()`. Lets containers like
  `BranchedShellRouter` hold heterogeneously typed routers
  (Dart's generic invariance makes a `List<GateRouter<? extends
  GateRoute>>` impossible without erasure). Most apps won't reference
  it directly; it's the shape the shell needs.

- **`context.branchedShell()`** — accessor for the enclosing
  [BranchedShellRouter] inside a branched shell, for programmatic
  `switchTo` etc.

## 0.3.2 — Patch

### Fixed

- `dispose()` mid-flow no longer throws `A GateRouter was used after
  being disposed`. Trace: `dispose()` cleared the flow state and
  called `super.dispose()`, but the `finally` block in the awaiting
  `run<T>` then ran a `notifyListeners()` on the now-disposed
  notifier. The `finally` now checks whether the router still owns
  the flow state (`identical(_flowCompleter, completer)`) before
  cleaning up — when `dispose` got there first, the check is false
  and the cleanup is skipped.
- Test `fromStack rejects empty` was passing the factory as a
  function reference (`expect(GateRouter<_R>.fromStack, throwsArgumentError)`),
  which `expect` invoked with zero arguments and threw
  `NoSuchMethodError` instead of `ArgumentError`. Now wrapped in a
  closure: `expect(() => GateRouter<_R>.fromStack(const []), throwsArgumentError)`.

## 0.3.1 — Patch

### Fixed

- `context.router<R>()` was a compile error in 0.3.0: the extension
  body returned `RouterScope.of<R>(this)` instead of accessing the
  scope's `.router` field. Now returns `GateRouter<R>` as declared.

### Changed

- Example app: replaced `mixin RequiresAuth on AppRoute {}` with
  `abstract interface class RequiresAuth {}` and switched route
  classes from `with RequiresAuth` to `implements RequiresAuth`.
  A mixin declared `on AppRoute` becomes a subtype of `AppRoute`
  from the exhaustiveness checker's perspective, which then insists
  on a `RequiresAuth()` pattern in every `switch` over `AppRoute`
  even when every concrete final class is enumerated. Marker
  interfaces that live outside the sealed hierarchy don't have
  this problem. Runtime behaviour of the auth guard
  (`r is RequiresAuth`) is unchanged. (No library API change.)

## 0.3.0 — Modal flows, multi-route URLs, unified router access

Three additions. One small breaking change in the parser constructor.

### Added

- **`GateModalRoute<T>` and `await router.run<T>(...)`.** A modal flow
  is a route variant on your sealed hierarchy that *also* implements
  `GateModalRoute<T>` to declare its result type:

  ```dart
  final class ConfirmAddToCart extends AppRoute
      implements GateModalRoute<int> {
    const ConfirmAddToCart(this.productId);
    final String productId;
    @override
    List<Object?> get props => [productId];
  }

  final qty = await router.run(ConfirmAddToCart('sku-42'));
  if (qty != null) /* user confirmed */
  ```

  `router.run<T>(flow)` creates a sub-router for the flow's own stack
  (push/pop within the flow work normally), returns `Future<T?>`, and
  resolves when a flow screen calls `context.completeFlow<T>(value)`
  (or `context.dismissFlow()` / system back at flow root → `null`).
  Flow screens are rendered over the main UI by the user-supplied
  `modalBuilder` on `GateRouterDelegate`. v0.3 supports one flow at a
  time (nested flows throw `StateError`).
- **`GateStackCodec<R>` — multi-route URL codec.** A single URL can
  decode into a stack of more than one frame, so deep links can
  restore sensible back-button behaviour. `/settings` can decode to
  `[MainShell, Settings]` so back returns to the shell instead of
  exiting the app. `GateSingleStackCodec<R>` wraps the v0.1 / v0.2
  `GateCodec<R>` for migration without rewriting the codec.
- **Unified `context.router<R>()`.** A new `RouterScope` inherited
  widget exposes whichever `GateRouter` is in effect at a point in the
  tree — the flow router inside a modal, the branch router inside a
  shell, the main router elsewhere. `context.branchRouter<R>()` from
  v0.2 still works.
- **`GateInnerNavigator<R>` — reusable navigator widget.** The
  "Navigator bound to a GateRouter" pattern, exposed as a public
  primitive. Used internally by `GateShell` and the modal-flow
  rendering inside `GateRouterDelegate`; available for embedding in
  custom router-aware composite widgets.
- **`context.completeFlow<T>(value)` / `context.dismissFlow()`.**
  In-flow accessors for resolving the awaiter on the host router.

### Breaking

- `GateRouteInformationParser` now takes a `GateStackCodec<R>` and a
  `List<R> fallback`. Migration paths:
  - **Use the new stack codec directly.** Implement `GateStackCodec`
    instead of `GateCodec`.
  - **Use `.single` named constructor.** Pass your existing
    `GateCodec` and a single-route `fallback`:
    `GateRouteInformationParser<R>.single(codec: ..., fallback: ...)`.
- The shell context extension is renamed `GateBuildContextX` →
  `GateShellBuildContextX` to make room for the new unified
  `GateRouterContextX` (which provides `context.router<R>()`).
  Method names (`branchRouter`, `shellRouter`) are unchanged, so
  call sites do not need updating.

## 0.2.0 — Guards, equality, and shells

Three additions, one breaking change.

### Added

- **`GateGuard<R>` pipeline.** Pass `guards: [...]` to `GateRouter` / `ShellRouter` /
  `GateShell`. Each guard is `FutureOr<List<R>> Function(current, proposed)`;
  guards run in order, each receiving the previous's output. Return the
  proposed stack unchanged to allow, a different stack to redirect, or
  `current` to refuse. Sync or async — async guards make the navigation
  async, sync guards complete synchronously. Guards do not run on
  navigator-driven pops (system back); they run on `push`/`pop`/`replace`/
  `set`/`popUntil` and on incoming deep links via `setNewRoutePath`.
- **Default `props`-based equality on `GateRoute`.** Override `props` with
  the fields you want compared; `==`/`hashCode` come for free. No-field
  variants don't need anything — `Home() == Home()` works out of the box.
  Eliminates the manual equality boilerplate from v0.1 examples.
- **`ShellRouter<R>` and `GateShell<R>`.** Multi-branch navigation with
  per-tab back stacks, independent routers, optional branch-scoped
  state (`branchScope: (context, i, child) => MyProvider(...)`), and
  Android back-button handling via `PopScope`: in-branch back unwinds
  the branch stack; at branch root, back falls through to the parent
  router (which may pop the shell itself). `ShellScope` exposes both the
  shell router and the active branch's router via inherited widget;
  `context.branchRouter<R>()` and `context.shellRouter<R>()` are the
  convenience accessors.
- **Identity-preserving stack diff.** When you push a route, existing
  pages keep their navigator state. Previously, every mutation
  rebuilt every entry — fine for v0.1 but wasteful. Now the diff
  preserves entries whose route at the same position is equal.

### Breaking

- **Router mutations now return `Future`**: `push`, `pop`, `replace`,
  `set`, and `popUntil` return `Future<void>` (or `Future<bool>` for
  `pop`). Migration: if you don't have async guards, fire-and-forget
  works — `router.push(x)` without an `await` is fine; the Future
  completes synchronously. If you check the return of `pop`, await it.

### Fixed

- Rapid concurrent pops without `await` now unwind the stack one
  level per call, instead of silently coalescing into a single pop.
  Each operation's target is computed at task-run time, not at
  call-site time.

## 0.1.0 — Foundation

Initial release.

- `GateRoute` base marker for sealed route types.
- `GateRouter<R>` state container with `push`, `pop`, `replace`, `set`, `popUntil`.
- `GateRouterDelegate<R>` plugging into `MaterialApp.router`.
- `GateRouteInformationParser<R>` for URL → route stack restoration.
- `GateCodec<R>` interface for URL ↔ route mapping.
- Identity-stable internal page keying so duplicate equal routes on the stack coexist.
- Pure-Dart unit tests for the navigation state.
