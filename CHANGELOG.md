# Changelog

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

### Deferred to 0.7+

- Adaptive layout policies (master-detail responsive)
- Direction-aware and shared-element transitions
- Nested modal flows (relaxing the v0.3 "one flow at a time"
  constraint)
- A composition helper for prefix-based module URL routing
  (currently the host's codec assembles module URLs by hand)

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

### Deliberately not shipped (v0.6+)

- Composable `RouteModule`s mountable at URL prefixes.
- Adaptive layout policies on routes (master-detail responsive).
- Direction-aware and shared-element transitions.
- Nested modal flows.

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

### Deliberately not shipped (v0.5+)

- Per-branch URLs reaching into shell stacks (e.g. `/app/home/products/sku-42`).
  Requires restructuring the configuration type beyond `List<R>`.
- Composable `RouteModule`s mountable at URL prefixes.
- Adaptive layout policies on routes (master-detail responsive).
- Direction-aware and shared-element transitions.
- Nested modal flows.

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

### Deliberately not shipped (v0.4+)

- Composable `RouteModule`s mountable at URL prefixes.
- Adaptive layout policies on routes (master-detail responsive).
- Direction-aware and shared-element transitions.
- Per-branch typed route subtypes inside a shell.
- Nested modal flows.
- Per-branch URLs reaching into shell stacks.

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

### Deliberately not shipped (v0.3+)

- Modal sub-flows with typed result returns (`await router.run<T>(...)`).
- Composable `RouteModule`s mountable at URL prefixes.
- Multi-route URL encoding (deep stacks like `/a/b/c` decoding to multiple frames).
- Adaptive layout policies on routes (master-detail responsive).
- Direction-aware and shared-element transitions.
- Per-branch typed route subtypes inside a shell.

## 0.1.0 — Foundation

Initial release.

- `GateRoute` base marker for sealed route types.
- `GateRouter<R>` state container with `push`, `pop`, `replace`, `set`, `popUntil`.
- `GateRouterDelegate<R>` plugging into `MaterialApp.router`.
- `GateRouteInformationParser<R>` for URL → route stack restoration.
- `GateCodec<R>` interface for URL ↔ route mapping.
- Identity-stable internal page keying so duplicate equal routes on the stack coexist.
- Pure-Dart unit tests for the navigation state.
