# Changelog

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
