# Changelog

## 0.22.0

### Added

- **State restoration** — survive an OS process-kill (iOS background-kill,
  Android low-memory) and relaunch where the user left off. Opt in with
  `restorationScopeId` on your `MaterialApp`.
  - **Stack restoration (URL/codec apps)** rides Flutter's `Router` restoration
    — no kaisel code needed beyond the app `restorationScopeId`.
  - **`restorationScopeId`** on `KaiselRouterConfig` / `KaiselRouterDelegate`
    gives the main stack a restoration scope; shell branches and modules each get
    their own automatically, so a page's inner widget state (scroll offset, text
    fields via `RestorationMixin`) survives the restart.
  - **`KaiselRoute.restorationId`** (from `kaisel_core`) feeds each page's id —
    defaults to the route's `routeName` for parameterless routes.
  - **`restoreRoute` — codec-less stack restoration.** Apps with no URL codec can
    restore the **main** stack with a small `(name, props) => route` rebuild
    function; kaisel saves `routeName` + `props` to a restoration bucket and
    replays it. (Nested shell/module state still needs a codec.)

### Changed

- Requires `kaisel_core: ^0.22.0` (for `KaiselRoute.restorationId`).

## 0.21.0

### Added

- **`context.back()` / `context.historyGo(int delta)`** — history-aligned back
  navigation so the browser's own Back/Forward buttons keep mirroring the app
  stack, even across several pops in a row. On the web it moves the browser
  history *pointer* (a true Back) and lets the inbound URL restore the stack
  through your codec — so the screen you leave becomes a *forward* entry instead
  of a lingering duplicate. Unlike `pop` (which adds a history entry, the
  ecosystem default), `back` makes multi-level back navigation track the app
  stack. It reads the engine's `serialCount` to avoid stepping out of the app on
  a cold deep link, and **falls back to `pop`** off the web, without a codec, or
  when there's no app history behind the current entry. Reach for it where you
  want browser history to track multi-level back navigation; `pop` stays the
  choice when a screen must return a `pushForResult` value. Adds a web-only
  `package:web` dependency (via conditional import — `kaisel_core` and non-web
  builds never reference it).
- **Web-aware default page transition.** On the web the default page now uses a
  quick fade instead of `MaterialPage`'s OS-derived slide, which feels out of
  place in a browser; native transitions are unchanged off the web. Override with
  `webTransition:` on `KaiselRouterConfig` / `KaiselRouterDelegate`
  (`KaiselWebTransition.fade` default, `.none`, or `.platform` to keep the OS
  transition). A custom `pageWrapper` is unaffected.
- **Lazy shell branches** — `KaiselBranchedShell.specs(lazy: true)` builds each
  branch on first activation instead of all up front, and keeps built branches
  alive so per-tab state still survives switches. Backed by a new
  `BranchedShellRouter.lazy` controller that materialises a branch (its router)
  on demand through `current` / `switchTo` / `restoreFromConfig`. The eager
  `IndexedStack` stays the default.
- **Deferred (code-split) branches** — `KaiselBranchSpec.deferred` loads a
  branch's code on first activation, behind a `deferred as` import. It shows a
  `placeholder` while `loadLibrary` runs, swaps in the screens once it resolves,
  and renders `errorBuilder` on failure — the `errorBuilder` is passed a `retry`
  callback, since a kept-alive branch can't recover on its own. Route values and
  `initial` stay non-deferred, so back handling, URL capture, and deep links
  keep working while the code loads. Requires `lazy: true`.
- **Custom lazy container** — `lazyBranchContentBuilder`
  (`KaiselLazyBranchContentBuilder`) is the lazy counterpart to
  `branchContentBuilder`: instead of a pre-built widget list it hands you a
  `buildBranch(context, index)` callback that materialises a branch on demand,
  so a custom container (e.g. a lazy `PageView`) can build and keep alive what
  it chooses.
- **DevTools shows lazy branch build-state** — the inspector snapshot reports
  every branch by index with a `built` flag (read without materialising dormant
  branches), so you can watch lazy tabs build as they're first visited, and the
  branch/no-op panels stay index-accurate for a lazy shell.

### Changed

- **Replace-style navigation overwrites the browser history entry instead of
  adding one.** On the web, `replaceTop` / `set` (and the replace half of
  `pushOrReplaceTop`) now report a *replace*, so they overwrite the current
  history entry rather than pushing a new one — matching go_router's `go` /
  `replace`. `push` still adds an entry; inbound restore (browser back/forward,
  deep links) is unchanged. Works for both `context.*` verbs and bare `router.*`
  calls. ([#25]) `pop` deliberately stays a *push* (the ecosystem default) — see
  `context.back()` above for history-aligned back navigation ([#27]).
- **Replaces inside a shell branch or module are reported as replaces**
  ([#28]). The route-information provider reads the delegate's disposition, which
  tracks whichever router — the main router or the active nested handle —
  committed last. A `replaceTop` inside a branch overwrites the entry; switching
  branches still adds one.

### Dependencies

- Requires `kaisel_core: ^0.21.0` (for the `replacesHistoryEntry` hints and the
  pop-is-a-push disposition).
- Adds `web: ^1.1.0` — web-only, behind a conditional import.

[#25]: https://github.com/Mastersam07/kaisel/issues/25
[#27]: https://github.com/Mastersam07/kaisel/issues/27
[#28]: https://github.com/Mastersam07/kaisel/issues/28

## 0.20.0

### Changed

- **Modal flows now render as routes on the main navigator**, replacing the
  experimental root overlay host from 0.19.0. A `run<T>` flow is a transparent
  page on the same navigator as the main stack, so dialogs and bottom sheets
  follow Flutter's normal single-overlay rules:
  - `showDialog` / `showModalBottomSheet` render **above an active flow for both
    `useRootNavigator` values** (0.19.0's overlay only handled the default
    `true`), including a dialog shown from the `navigatorKey` context.
  - The main navigator's `observers` now see a flow's open/close (`didPush` /
    `didPop` on the flow's route), so a `RouteObserver` / `RouteAware` on the
    main stack observes the flow boundary. Internal flow screens remain on the
    flow's own inner navigator.
  - System back unwinds dialog → flow inner screens → flow → main, in order.

  `run<T>` / `KaiselModalRoute<T>` / `completeFlow` / `dismissFlow` /
  `modalBuilder` are unchanged at the call site. Observable behavior does shift:
  a flow now animates in/out, traps focus, emits modal semantics, allows
  cross-boundary `Hero`s, and responds to a raw `Navigator.pop` (which dismisses
  it with `null`). A flow page carries the flow route's `name` / `arguments` so
  it is identifiable to observers.

### Added

- **`KaiselPageWrapperContext.isFlow`** — a `pageWrapper` can give a flow its own
  entrance transition by branching on `isFlow` and returning a page (typically
  non-opaque, so the main stack shows behind the scrim); the framework otherwise
  uses an instant, transparent flow page. A custom flow page should forward
  `name` / `arguments` from `ctx.route` to stay observable.

## 0.19.0

### Added

- **`context.pushForResult<T>(route)` and `context.pop([result])`** — typed
  results from a screen on the main stack, the Flutter-layer surface over
  `KaiselRouter.pushForResult`. The screen stays a normal route in the same
  navigator, so root-navigator dialogs, a shared observer, and ordinary
  navigation all behave as usual. Reach for it instead of `run<T>` when a screen
  needs to return a value without being lifted into a modal flow's separate
  navigator.

- **Root overlay host for dialogs over modal flows.** _[Experimental.]_ The
  delegate wraps the app in a root `Navigator` above the main stack and all flow
  layers, so `showDialog` / `showModalBottomSheet` (whose `useRootNavigator`
  defaults to `true`) render above an active `run<T>` flow instead of behind it —
  including a dialog shown from the `navigatorKey` context the app attaches to its
  config. System back dismisses a hosted dialog before unwinding the flow. The
  presentation model is still evolving; don't depend on the exact navigator
  structure yet.

### Changed

- Requires `kaisel_core: ^0.18.0` (for `pushForResult` / `pop(result)`).

## 0.18.0

### Added

- **"Who navigated" in DevTools** — every entry in the Transitions log now
  carries the app call site that triggered it. In debug, each `push` / `pop` /
  `set` / `replaceTop` and each shell `switchTo` records the caller's stack;
  `debugSnapshot()` reports the app frames (kaisel, Flutter, and SDK frames
  trimmed away) on `KaiselRootSnapshot.origin`, and the extension shows the
  closest frame inline, expandable to the full trace. Turns "which tab am I on
  and why" into one glance. Debug-only; compiled out of release.

### Fixed

- **`initial:` is now honored on a normal launch**, even with a `codec`. The
  platform's default route (`/`) was always decoded and applied at startup, so a
  router whose `initial` mapped elsewhere (e.g. a splash) would render that
  screen and then flash straight to the decoded `/` route before its own onward
  navigation could run. A bare launch (no path segments) now keeps `initial:`; a
  real cold-start deep link still wins. No change for apps whose `initial`
  already maps to `/`.

- **A deep link to a shell branch the current build doesn't mount no longer
  throws.** `BranchedShellRouter.restoreFromConfig` treated an out-of-range
  branch index as a fatal `RangeError`, so a codec that addresses a branch
  present only on some form factors (e.g. a desktop-only tab opened on a build
  with fewer branches) would abort the restore and silently strand the user on
  the default branch. The restore now skips an unknown branch — with a debug
  warning explaining why — and applies the rest of the configuration.
  Programmatic `shell.switchTo(badIndex)` still throws, since that index comes
  from app code rather than an external URL.

### Changed

- Requires `kaisel_core: ^0.17.0` (for the navigation-origin APIs).

## 0.17.0

### Added

- **`navigatorKey`** on `KaiselRouterConfig` / `KaiselRouterDelegate` — pass a
  `GlobalKey<NavigatorState>` for the main navigator (e.g. to hand to a
  third-party SDK), or read the auto-created one via `config.navigatorKey` /
  `config.navigator` for raw `NavigatorState` access. For context-free
  *navigation*, the typed `router` stays the idiomatic handle.

## 0.16.0

### Added

- **DevTools read-write** — the kaisel DevTools extension can now *drive* the
  app, not just inspect it. Behind a **Write** toggle (off by default, since it
  mutates the running app): pop the main stack, switch a shell branch, dismiss
  the active flow, **apply** a deep-link URL (decoded through your codec and
  navigated to), and **time-travel** — jump back to any previous stack from a
  recorded history. Debug-only, like the rest of the inspector.
- **Route names for observers** — pages now carry `settings.name` (from
  `KaiselRoute.routeName`, defaulting to the runtime type) and the route in
  `settings.arguments`, so off-the-shelf `NavigatorObserver`s like
  `FirebaseAnalyticsObserver` can identify the screen. Override `routeName` with
  a string literal for a custom or `--obfuscate`-stable name. (Named `routeName`,
  not `name`, so it never clashes with a domain field on your route.)

### Changed

- Requires `kaisel_core: ^0.16.0` (for the command + history APIs and the
  `routeName` getter).

### Fixed

- **`context.pop()` inside a `showModalBottomSheet` / `showDialog` now closes
  that overlay** instead of popping the route beneath it. On a kaisel page it
  still pops the typed router stack (guards run) as before. To pop the
  underlying route from inside an overlay, call `pop()` on a held `KaiselRouter`
  (e.g. `context.router<R>().pop()`).

## 0.15.1

### Fixed

- Require `kaisel_core: ^0.14.0`. The DevTools inspector added in 0.15.0 uses
  APIs introduced in `kaisel_core 0.14.0`, but the constraint was still
  `^0.13.0` — so against a published `kaisel_core` the package failed to resolve
  and analyse (0.15.0 scored poorly on pub.dev for this reason).

## 0.15.0

### Added

- **DevTools extension** — kaisel now ships a zero-integration Dart/Flutter
  DevTools extension. In debug, `KaiselRouterDelegate` auto-registers with an
  inspector and emits navigation snapshots; open DevTools to get a live
  **kaisel** panel showing the main stack (with a diff highlight), shell
  branches, mounted modules, active flows, the last guard-pipeline run, a
  **Problems** tab that flags no-op `replaceTop`s (the missing-`props` bug) and
  broken codec round-trips, a transitions log, the current URL plus a deep-link
  **decode** preview, and adaptive master-detail absorption. No setup — depend on
  kaisel and open DevTools. Debug-only: the hook is `kDebugMode`-gated and
  compiled out of release builds, adding no runtime cost or dependencies.

- **Navigator observers** — `observers:` on `KaiselRouterConfig` and
  `KaiselRouterDelegate` takes a `KaiselObserversBuilder`
  (`List<NavigatorObserver> Function()`). kaisel calls it once per navigator —
  the main stack and each shell branch, module, and active flow — so each gets
  its own fresh `NavigatorObserver` instance (one instance can't span
  navigators). For analytics, Sentry, `RouteObserver`, and the like. If you
  want a single unified "current screen" stream instead of one observer per
  navigator, listen to the router(s) directly — the stack is observable state.

## 0.14.1

### Added

- **`KaiselRouterConfig.adaptive`** — a `KaiselRouterConfig` constructor that
  takes an adaptive page builder (the `(context, route, stack)` form), for apps
  whose **main** router is a top-level adaptive master-detail. Mirrors
  `KaiselRouterDelegate.adaptive`, which the default `KaiselRouterConfig`
  constructor didn't cover. (Adaptive layouts *inside* a shell branch use
  `KaiselBranch.adaptive` / `KaiselBranchSpec.adaptive` and don't need this.)

### Examples

- All example entry points now use `KaiselRouterConfig` for setup — previously
  the flagship `main.dart` and four others still demonstrated the manual
  `KaiselRouterDelegate` + hand-rolled parser the config replaces.

## 0.14.0

Navigation ergonomics — terser setup and call sites, and a single shell
accessor. Additive except for the removed split shell accessors (pre-1.0, so no
deprecation cycle).

### Added

- **`KaiselRouterConfig<R>`** — a `RouterConfig` that bundles the router,
  delegate, and (when given a `codec:`) the URL parser + platform provider into
  the single object `MaterialApp.router(routerConfig:)` expects. Hold it as a
  top-level `final` for an app-lifetime router: no `StatefulWidget`, no manual
  delegate or parser, no `dispose`. `config.router` exposes the bundled
  `KaiselRouter<R>`. The explicit `KaiselRouterDelegate` + parser path is
  unchanged.
- **Terse `context.*` navigation** — `context.push` / `pop` / `replaceTop` /
  `pushOrReplaceTop` / `set` / `run<T>` on `BuildContext`, a deliberate
  convenience over the typed `context.router<R>().<verb>` (which stays the
  idiomatic default). Each resolves the nearest router whose route type accepts
  the argument (a runtime walk up the tree); the trade is that a wrong-family
  route throws at runtime instead of failing to compile.
- **`context.shell()` → `KaiselShellController`** — one accessor for either
  shell flavour, exposing `switchTo`, `activeBranch`, `branchCount`, and
  `current` (the active branch's navigator, so chrome can read the active stack
  and pop it without holding a router reference).
- **`KaiselBranchedShell.specs(...)` + `KaiselBranchSpec<R>`** — declare a
  branched shell from per-branch `initial` + `builder` specs; the shell creates,
  owns, and disposes one router per branch (each branch's stack still survives
  tab switches), so you never construct a `KaiselRouter` or
  `BranchedShellRouter`. `KaiselBranchSpec.adaptive(...)` for adaptive branches.
  The explicit `KaiselBranchedShell(shell:, branches:)` form stays for when you
  need to hold the branch routers.
- **`KaiselBranchedShell.branchContentBuilder`** — optional override for how the
  branches are laid out. Defaults to an `IndexedStack` (all branches mounted,
  state preserved); pass one to use a `PageView` or any other container while
  keeping the shell's back-button routing, scopes, and URL wiring. When you
  override it, preserving per-branch state is yours to handle.

### Removed (breaking)

- **`context.branchedShell()`, `context.shellRouter<R>()`,
  `context.branchRouter<R>()`** and the **`BranchedShellScope` / `ShellScope`**
  inherited widgets. Use `context.shell()` (and `context.shell().current`). The
  pre-1.0 release skips a deprecation cycle.

## 0.13.1

### Added

- **`KaiselListenableBuilder<R>`** and **`KaiselRouter.asListenable()`**.
  Because `kaisel_core` is Flutter-free, a `KaiselRouter` is not a Flutter
  `Listenable` and can't be passed to `ListenableBuilder` directly. The new
  widget rebuilds on every router notification; the `asListenable()`
  extension returns a stateless `Listenable` pass-through for use with
  `ListenableBuilder` / `AnimatedBuilder`.

## 0.13.0 — Renamed to kaisel

The package was renamed from **gate** to **kaisel**. This is a
mechanical rename with **no behavioural changes** — same router, same
semantics — but it is a hard breaking change. Also now licensed under
**Apache-2.0**.

### Migration

- **Package:** `gate` → `kaisel`, and the satellites `gate_core` →
  `kaisel_core`, `gate_devtools` → `kaisel_devtools`, `gate_lint` →
  `kaisel_lint`.
  ```yaml
  dependencies:
    kaisel: ^0.13.0   # was: gate: ^0.12.0
  ```
- **Imports:** `package:gate/gate.dart` → `package:kaisel/kaisel.dart`
  (and `package:gate_core/...` → `package:kaisel_core/...`).
- **Symbols:** every `Gate*` type is now `Kaisel*` —
  `GateRoute` → `KaiselRoute`, `GateRouter` → `KaiselRouter`,
  `GateRouterDelegate` → `KaiselRouterDelegate`, `GateGuard` →
  `KaiselGuard`, `GateShell` → `KaiselShell`, `GateModalRoute` →
  `KaiselModalRoute`, `GatePageScope` → `KaiselPageScope`, and so on.
  Names without the `Gate` prefix (`ShellRouter`, `RouterScope`,
  `BranchedShellRouter`, `FlowScope`, …) are unchanged.

A find-and-replace of `Gate` → `Kaisel` and `package:gate` →
`package:kaisel` covers essentially all app code.

The entries below are retained for history; their `Kaisel*` names
reflect the post-rename API.

## 0.12.0 — Page scope for descendants

An additive release: a framework-provided
`KaiselPageScope` `InheritedWidget` exposes the wrapper context to
descendant widgets. v0.11 gave the page-wrapping layer enough info
to choose transitions; v0.12 gives the descendant widgets enough
info to make context-aware decisions ("am I the only rendered
page?", "what's the route below me?").

### API

- **`KaiselPageScope`**: new `InheritedWidget` in
  `src/kaisel_page_scope.dart`. Exposes `route` (typed as
  `KaiselRoute`), `position`, `stackLength`, `previous`, and the
  convenience getters `isTop` / `isBottom`. Read with
  `KaiselPageScope.maybeOf(context)` (returns null if outside a
  kaisel page) or `KaiselPageScope.of(context)` (asserts there is
  one).

- The framework injects `KaiselPageScope` at every wrap call site:
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
`KaiselPageScope.maybeOf(context)?.isBottom` directly. The example's
`AdaptiveContext` is gone.

The same pattern applies to "back to X" labels (read
`scope.previous`), AppBar fading per `isTop`, and route-aware
deep-nested widgets that don't want to thread the route through
constructors.

### Example

`example/lib/main_adaptive.dart` no longer ships its own
`AdaptiveContext` class. `BookDetailScreen` reads
`KaiselPageScope.maybeOf(context)?.isBottom` instead. The behaviour
is identical: at narrow widths the rendered stack is
`[BookList, BookDetail]` and `isBottom == false` so the back arrow
shows; at wide widths the BookDetail page absorbs BookList, the
rendered stack is `[BookDetail]` only, `isBottom == true` so the
back arrow hides.

### Caveat

A custom `pageWrapper` that constructs a Page with a different
child (replacing `ctx.child` entirely instead of passing it
through) is responsible for re-wrapping in `KaiselPageScope` if it
wants descendants to see it. The common pattern of
`Page(child: ctx.child)` just works.

---

## 0.11.0 — Direction-aware transitions and adaptive ergonomics

Two changes. The headline is a breaking change to the page-wrapper
signature that enables direction-aware transitions. The second adds
`pushOrReplaceTop` for in-place master-detail swaps.

### Direction-aware transitions

The `KaiselPageWrapper` typedef has changed signature. Previously it
took three positional arguments `(R route, Widget child, LocalKey
key)`. It now takes a single `KaiselPageWrapperContext<R>` with the
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

`KaiselPageWrapperContext` lives in `src/kaisel_page_wrapper.dart`,
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

- **`KaiselRouter.pushOrReplaceTop(R route, {bool Function(R)? when})`**:
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

- **`KaiselRouter.replace` renamed to `KaiselRouter.replaceTop`**. The
  method has always only touched the top entry; the longer name
  makes that immediate at the call site.

### Example

The adaptive demo uses `pushOrReplaceTop` in its `_selectBook`
helper. Run with `flutter run -t lib/main_adaptive.dart` from the
example directory.

---

## 0.10.0 — Nested modal flows

v0.3 introduced `router.run<T>(...)` for typed modal sub-flows but
restricted to one flow at a time. A second `run` call threw a
`StateError`. v0.10 reshapes the API around a stack of flows: nested
runs push onto the stack, completions pop LIFO, and the delegate
renders one modal layer per active flow. A payment flow can itself
`run` an "add card" sub-flow; an auth flow can open a "verify
identity" sub-flow.

### API

- **`KaiselActiveFlow<R>`**: a read-only view of one entry in the
  active flow stack. Exposes the flow's defining route and its
  sub-router. The completer is private so callers can't bypass the
  LIFO completion discipline.

- **`KaiselRouter.activeFlows`**: returns `List<KaiselActiveFlow<R>>`,
  ordered oldest-first (bottom of the modal stack to topmost). The
  delegate renders one overlay layer per entry. The last entry is
  the flow that `completeFlow` and `dismissFlow` resolve.

- **`KaiselRouter.hasActiveFlow`**: convenience for
  `activeFlows.isNotEmpty`. Unchanged from v0.3.

- **`KaiselRouter.run<T>`**: no longer throws when a flow is active.
  Appends to the stack.

- **`KaiselRouter.completeFlow<T>(value)`** and **`dismissFlow()`**:
  resolve the topmost flow. Only the topmost can be completed via
  this API. To unwind multiple flows, complete the topmost, await
  it, then complete the next.

- **Removed**: the v0.3 `activeFlowRoute` and `activeFlowRouter`
  singleton accessors. Use `activeFlows.last.route` and
  `activeFlows.last.router` (or `lastOrNull` for a null-safe form).

### Delegate

`KaiselRouterDelegate.build` renders one modal overlay layer per
active flow. Each layer has its own `KaiselInnerNavigator` (with a
stable per-flow `GlobalKey`), its own `RouterScope<R>`, its own
`FlowScope`, and its own `PopScope`. The topmost layer ends up
deepest in the widget tree, so its `PopScope` sees Android back
gestures first.

The private `_ModalOverlay` widget that v0.3 used for the single-
flow case has been removed; its responsibilities are inlined into a
`_buildFlowLayer` method on the delegate.

`KaiselRouter.dispose` resolves every pending flow with `null`.

### Pop semantics with nested flows

Each flow layer's `PopScope` works the same as the v0.3 single-flow
case: `canPop: false` (the layer intercepts back), and the handler
pops within the flow if possible, else dismisses the flow. With
nested flows, the topmost layer's PopScope handles back first; when
it dismisses, the layer below resumes control. Pop unwinds one flow
at a time.

### Example app

`example/lib/main_nested_flows.dart` demonstrates nested flows: a
payment flow opens an "add card" flow on top of itself, with both
modal layers visible at once. Run with
`flutter run -t lib/main_nested_flows.dart` from the example
directory. See `example/README.md`.

---

## 0.9.0 — Adaptive layouts inside shells and modules

v0.9 extends the adaptive pipeline from the main `KaiselRouterDelegate`
(v0.8) into nested routers. Master-detail most often lives inside a
shell tab (a "products" tab whose list and detail collapse at wide
widths) or inside a feature module (a checkout flow's review/summary
side-by-side at wide widths), so v0.9 plumbs the adaptive pipeline
through the inner navigator shared by `KaiselBranch`, `KaiselShell`, and
`KaiselModuleMount` — any of them can now render absorbing pages.

Additive: v0.8 code still compiles and runs unchanged.

### Added

- **`KaiselBranch.adaptive`**: new named constructor on `KaiselBranch`.
  Takes a `KaiselAdaptivePageBuilder<R>` instead of a
  `KaiselPageBuilder<R>`. The branch's inner navigator goes through
  the adaptive pipeline.

  ```dart
  KaiselBranch<HomeRoute>.adaptive(
    router: homeRouter,
    pageBuilder: (context, route, stack) {
      final wide = MediaQuery.sizeOf(context).width >= 700;
      return switch ((route, stack.previous, wide)) {
        (ProductDetail(:final id), ProductList(), true) =>
          KaiselAbsorbingPage(
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

- **`KaiselShell.adaptive`**: new named constructor on `KaiselShell`
  (homogeneous shell). All branches share the adaptive builder
  (they share the route type). For per-branch adaptive
  configuration use `KaiselBranchedShell` with `KaiselBranch.adaptive`.

- **`RouteModule.buildAdaptivePage`**: new virtual method on
  `RouteModule` that returns a `KaiselPageResult`. Default
  implementation wraps `buildPage` as `KaiselStandalonePage(...)`, so
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
    KaiselPageResult buildAdaptivePage(
      BuildContext context,
      ShopRoute route,
      KaiselStackContext<ShopRoute> stack,
    ) {
      final wide = MediaQuery.sizeOf(context).width >= 700;
      return switch ((route, stack.previous, wide)) {
        (ProductDetail(:final id), ProductList(), true) =>
          KaiselAbsorbingPage(
            widget: KaiselMasterDetailScaffold(
              master: const ProductListScreen(),
              detail: ProductDetailScreen(id: id),
            ),
          ),
        _ => KaiselStandalonePage(buildPage(context, route)),
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

- **`KaiselInnerNavigator.adaptivePageBuilder`**: new optional
  parameter on the inner-navigator widget that shells and modules
  embed. Mutually exclusive with `pageBuilder`; one of the two
  must be provided. Custom hosts (your own composite widget that
  embeds a router) can pass either, same as the built-in ones.

### Changed

- `KaiselBranch.pageBuilder` and `KaiselShell.pageBuilder` are now
  private (`_pageBuilder`). They were public final fields in v0.8.
  No external code in the package or example reads them. If your
  app introspected the field, switch to constructing through the
  named constructors as before.
- The adaptive page-key type, `KaiselAdaptiveKey`, and the shared
  iteration helper `buildAdaptivePages` moved from the delegate's
  file into `kaisel_adaptive.dart`. Neither is part of the public
  barrel; noted only for anyone reading the internals.

### Pop semantics inside shells and modules

Shells and modules use `PopScope` + `router.pop()` directly to
handle the Android back gesture. They don't go through the
mixin's `popRoute` → `Navigator.maybePop` path the main
delegate uses (see v0.8). The PopScope's `canPop` reads `router.canPop`,
which reflects the logical stack regardless of how many visible
pages absorption produced. So absorbing inside a shell branch or
module is correctly back-poppable by construction. No
`popRoute`-style override was needed at this level.

### Scope

- `KaiselShell.adaptive` is homogeneous: all branches share the
  adaptive builder, matching the homogeneous `KaiselShell` model.
  Per-branch adaptive configuration goes through `KaiselBranchedShell`
  + `KaiselBranch.adaptive`.
- The adaptive iteration is identical at the main delegate, shell
  branch, and module mount levels — same `buildAdaptivePages`
  helper, same `KaiselAdaptiveKey` semantics. A `KaiselAbsorbingPage`
  inside a shell branch absorbs entries within that branch's
  stack, not across the host stack.

---

## 0.8.0 — Adaptive layouts

The headline is `KaiselRouterDelegate.adaptive`, a new constructor that
takes a stack-aware page builder. Adaptive page builders can decide
to render an *absorbing* page that collapses one or more entries
below it on the stack into a single rendered page. The canonical
use is master-detail at wide breakpoints: the detail route absorbs
the master into one widget rather than appearing on top of it.

Additive: v0.7 code still compiles and runs unchanged.

### Added

- **`KaiselRouterDelegate.adaptive`**: new named constructor. Takes a
  `KaiselAdaptivePageBuilder` instead of a `KaiselPageBuilder`. The
  main stack goes through the adaptive pipeline. Modal flows
  continue to render through the simple per-route path; if you use
  an adaptive delegate with `router.run<T>(...)`, the modal builder
  synthesises a simple builder from your adaptive one (calling it
  with a single-entry stack context and using the resulting
  widget; the `absorbing` count is ignored on the modal path).

  ```dart
  KaiselRouterDelegate<AppRoute>.adaptive(
    router: router,
    builder: (context, route, stack) {
      final wide = MediaQuery.sizeOf(context).width >= 700;
      return switch ((route, stack.previous, wide)) {
        (ProductDetail(:final id), ProductList(), true) =>
          KaiselAbsorbingPage(
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

- **`KaiselPageResult`**: sealed result type returned by an adaptive
  builder. Two variants: `KaiselStandalonePage(widget)` for the
  default 1:1 stack-to-pages case, `KaiselAbsorbingPage(widget,
  absorbing: n)` to render a widget that subsumes `n` entries
  below.

- **`KaiselStackContext<R>`**: passed to the adaptive builder for
  each entry. Surfaces `stack`, `position`, `previous`, `next`,
  `isTop`, `isBottom`. Pattern-match on neighbours to decide what
  to render.

- **`KaiselAdaptivePageBuilder<R>`**: typedef for
  `KaiselPageResult Function(BuildContext, R, KaiselStackContext<R>)`.

- **`KaiselMasterDetailScaffold`**: small convenience widget. Rows a
  master and detail with an optional divider; takes a
  `masterFraction` for the split. Useful inside an absorbing
  page's widget. Replace with your own layout if you need
  different chrome.

### Page identity under absorption

The page produced by `KaiselAbsorbingPage` is keyed by the *lowest*
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

One edge case: when absorption collapses everything to
a single visible page, Flutter's `Navigator.maybePop` returns false
because there's no route below the current one. In v0.8,
[KaiselRouterDelegate.popRoute] tries the Navigator first and falls
through to `router.pop()` when it detects the absorbing state
(visible page count below the logical entry count). Without this,
the OS back gesture on a single-page absorbing state would bubble
out of the app instead of unwinding the logical stack. The simple
(non-adaptive) pipeline still uses the mixin's `popRoute` unchanged.

### Scope and limitations

- At this release, adaptive layouts are available at the main
  `KaiselRouterDelegate` only. Per-branch typed shells
  (`KaiselBranchedShell`) and modules (`RouteModule`) still use the
  simple per-route builder.
- The simple `KaiselPageBuilder` is still the default. The base
  `KaiselRouterDelegate(...)` constructor is unchanged.
- A user-supplied `pageWrapper` works with adaptive pages but
  doesn't get any signal that a page is absorbing. The wrapper
  sees the absorbing entry's route and the absorbed entry's key.
  If you need to know inside your wrapper, switch to standalone
  pages.

---

## 0.7.0 — Module URL composition

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

- **`ConfigCodecWithModules<R>`**: a `KaiselConfigCodec` that
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
composer is just a `KaiselConfigCodec` like any other.

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
  sealed class CheckoutRoute extends KaiselRoute { const CheckoutRoute(); }
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

- **`KaiselModuleMount<R>`** — the widget that mounts a `RouteModule`.
  Creates the module's typed `KaiselRouter<R>` internally, owns its
  lifecycle, installs a `RouterScope<R>` so descendants find the
  module's router via `context.router<R>()`. The host's main router
  is still reachable via `context.router<AppRoute>()` — same
  lookup-by-exact-type semantics as `KaiselBranch`.

  ```dart
  Widget _buildMainPage(BuildContext context, AppRoute route) =>
      switch (route) {
        CheckoutMount() => const KaiselModuleMount<CheckoutRoute>(
            module: CheckoutModule(),
          ),
        // ... other top-level routes
      };
  ```

- **`KaiselModuleConfig`** — captures a mounted module's internal
  stack so the URL can include it. Sibling to `KaiselShellConfig`
  under the new sealed `KaiselNestedConfig` base type.

### Changed (breaking)

- **`KaiselConfig.shellState` is gone. `KaiselConfig.nestedState` takes
  its place.** The configuration now carries a single sealed
  `KaiselNestedConfig?` — either a `KaiselShellConfig` or a
  `KaiselModuleConfig`. The "at most one nested kind on top of the
  main stack" property is enforced by the type system, not a
  runtime assertion. Pattern-match in your codec:

  ```dart
  // before (v0.5)
  Uri encode(KaiselConfig<AppRoute> config) {
    final shell = config.shellState;
    return shell != null
        ? _encodeShell(shell)
        : _encodeFlat(config.mainStack.last);
  }

  // after (v0.6)
  Uri encode(KaiselConfig<AppRoute> config) =>
      switch ((config.mainStack.last, config.nestedState)) {
        (MainShell(), final KaiselShellConfig shell)   => _encodeShell(shell),
        (CheckoutMount(), final KaiselModuleConfig m)  => _encodeCheckout(m),
        (Splash(), _)                                 => Uri(path: '/'),
        // ...
      };
  ```

  Codecs need a one-pass migration; rename `shellState` →
  `nestedState` and dispatch by config kind in `encode`. `decode`
  changes are mechanical (`shellState:` → `nestedState:`).

- **Host machinery unified.** The internal interfaces
  `KaiselShellHost` + `KaiselShellRestoreHandle` + `KaiselShellHostScope`
  collapse to `KaiselNestedHost` + `KaiselNestedHandle` +
  `KaiselNestedHostScope`. The delegate now keeps a single LIFO list
  of registered handles — the most recently registered is the
  active one — instead of a dedicated slot per nested kind. These
  types weren't exported from `package:kaisel/kaisel.dart`, so the
  rename is only visible to authors building custom nested routers.

- **Handles declare their config kind via `Type get configType`.**
  The delegate uses it to match pending state (from a cold-start
  deep link) to the right registered handle.

### Why the cleanup

The earlier two-slot model (`shellState`, `moduleState`) carried a
real structural cost: two parallel host interfaces, two parallel
scope widgets, and a runtime assertion duplicating what the type
system can already express. The sealed `KaiselNestedConfig` collapses
that into one field and states "at most one nested router rides the
URL" at the type level.

### Why modules

A core goal of Dart 3-native routing is "feature-team
plug-and-play": a feature ships with its own sealed subtype, its
own pageBuilder, and its own guards, and the host composes it.
Through v0.5 every route still had to live in the host's `AppRoute`;
v0.6 closes that gap. A payments SDK, a KYC
flow, an embedded checkout — all can ship as a `RouteModule` the
host mounts at a top-level route, with deep-linkable URLs.

---

## 0.5.0 — Per-branch URLs reaching into shell stacks

One headline feature, one breaking change (with a one-line migration).

### Added

- **`KaiselConfig<R>`** and **`KaiselShellConfig`** — the new
  configuration types that flow between the URL bar and the router.
  The configuration now describes both the main router's stack and
  (when a branched shell is mounted) the active branch's stack:

  ```dart
  KaiselConfig<AppRoute>(
    mainStack: [MainShell()],
    shellState: KaiselShellConfig(
      activeBranch: 0,
      activeBranchStack: [HomeRoot(), ProductDetail('sku-42')],
    ),
  )
  ```

  Encodes to `/home/products/sku-42` and round-trips back on deep
  link. Only the active branch's stack rides the URL — inactive
  branches keep their in-memory history so switching tabs and back
  doesn't reset them.

- **`KaiselConfigCodec<R>`** — codec interface for the richer
  configuration. Pattern-match on the main stack's top and the shell
  state to produce URLs; pattern-match on URI path segments to
  decode. The example shows the full pattern.

- **`StackToConfigCodec<R>`** — adapter that wraps a v0.4
  [KaiselStackCodec] so existing stack-only codecs work unchanged. Use
  it via `KaiselRouteInformationParser.fromStackCodec(...)` — that's
  the entire v0.4 → v0.5 migration if you don't need shell URLs.

- **`KaiselNavigator.stack` and `KaiselNavigator.restoreStack`** — the
  non-generic shell-friendly interface gains read/restore methods so
  `BranchedShellRouter` can capture and replay branch state across
  heterogeneously typed routers. `restoreStack` validates each route
  is assignable to the router's `R` at runtime; mismatches throw
  `ArgumentError` before any state mutates.

- **`BranchedShellRouter.captureConfig()` and `.restoreFromConfig(...)`**
  — bridge between the shell's runtime state and the URL. `restoreFromConfig`
  updates only the target branch and leaves inactive branches alone.

- **Shell-host registration via inherited widget** — a mounted
  `KaiselBranchedShell` discovers the enclosing `KaiselRouterDelegate`
  through `KaiselShellHostScope` and registers itself for URL
  capture/restore. Cold-start deep links into the shell are
  supported via a pending-state queue: if the URL arrives before
  the shell mounts, the delegate stores it and applies it when the
  shell registers.

### Changed (breaking)

- **`KaiselRouterDelegate<R>`** is now `RouterDelegate<KaiselConfig<R>>`
  instead of `RouterDelegate<List<R>>`, and **`KaiselRouteInformationParser<R>`**
  is parameterised the same way.

  **If you have a custom delegate or parser**, migrate the
  configuration type.

  **If you use the kaisel-provided ones with a `KaiselStackCodec`** (the
  v0.4 default), change one line at the wiring site:

  ```dart
  // v0.4
  KaiselRouteInformationParser<AppRoute>(
    codec: const AppStackCodec(),
    fallback: const [Splash()],
  )

  // v0.5 — same codec, minimal migration
  KaiselRouteInformationParser<AppRoute>.fromStackCodec(
    codec: const AppStackCodec(),
    fallback: const [Splash()],
  )
  ```

  To start using shell URLs, replace your `KaiselStackCodec` with a
  `KaiselConfigCodec` and pass it via the regular constructor.

## 0.4.0 — Per-branch typed routes in shells

One additive feature. No breaking changes.

### Added

- **`KaiselBranchedShell`, `KaiselBranch<R>`, `BranchedShellRouter`** — a
  shell whose branches have **different** sealed route types. Where
  the v0.2/v0.3 `KaiselShell<R>` requires every branch to share one
  route type (so pushing `DiscoverRoute` into the Home tab is a
  runtime concern), the branched shell typeschecks each branch
  independently:

  ```dart
  sealed class HomeRoute extends KaiselRoute { const HomeRoute(); }
  sealed class DiscoverRoute extends KaiselRoute { const DiscoverRoute(); }

  final homeRouter = KaiselRouter<HomeRoute>(initial: const HomeRoot());
  final discoverRouter = KaiselRouter<DiscoverRoute>(initial: const DiscoverRoot());
  final shell = BranchedShellRouter(branches: [homeRouter, discoverRouter]);

  KaiselBranchedShell(
    shell: shell,
    branches: [
      KaiselBranch<HomeRoute>(
        router: homeRouter,
        pageBuilder: (context, route) => switch (route) {
          HomeRoot() => const HomeScreen(),
          ProductDetail(:final id) => ProductDetailScreen(id: id),
        },
      ),
      KaiselBranch<DiscoverRoute>(
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

- **`KaiselNavigator`** — non-generic interface that `KaiselRouter`
  implements, exposing `canPop` and `pop()`. Lets containers like
  `BranchedShellRouter` hold heterogeneously typed routers
  (Dart's generic invariance makes a `List<KaiselRouter<? extends
  KaiselRoute>>` impossible without erasure). Most apps won't reference
  it directly; it's the shape the shell needs.

- **`context.branchedShell()`** — accessor for the enclosing
  [BranchedShellRouter] inside a branched shell, for programmatic
  `switchTo` etc.

## 0.3.2 — Patch

### Fixed

- `dispose()` mid-flow no longer throws `A KaiselRouter was used after
  being disposed`. Trace: `dispose()` cleared the flow state and
  called `super.dispose()`, but the `finally` block in the awaiting
  `run<T>` then ran a `notifyListeners()` on the now-disposed
  notifier. The `finally` now checks whether the router still owns
  the flow state (`identical(_flowCompleter, completer)`) before
  cleaning up — when `dispose` got there first, the check is false
  and the cleanup is skipped.
- Test `fromStack rejects empty` was passing the factory as a
  function reference (`expect(KaiselRouter<_R>.fromStack, throwsArgumentError)`),
  which `expect` invoked with zero arguments and threw
  `NoSuchMethodError` instead of `ArgumentError`. Now wrapped in a
  closure: `expect(() => KaiselRouter<_R>.fromStack(const []), throwsArgumentError)`.

## 0.3.1 — Patch

### Fixed

- `context.router<R>()` was a compile error in 0.3.0: the extension
  body returned `RouterScope.of<R>(this)` instead of accessing the
  scope's `.router` field. Now returns `KaiselRouter<R>` as declared.

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

- **`KaiselModalRoute<T>` and `await router.run<T>(...)`.** A modal flow
  is a route variant on your sealed hierarchy that *also* implements
  `KaiselModalRoute<T>` to declare its result type:

  ```dart
  final class ConfirmAddToCart extends AppRoute
      implements KaiselModalRoute<int> {
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
  `modalBuilder` on `KaiselRouterDelegate`. v0.3 supports one flow at a
  time (nested flows throw `StateError`).
- **`KaiselStackCodec<R>` — multi-route URL codec.** A single URL can
  decode into a stack of more than one frame, so deep links can
  restore sensible back-button behaviour. `/settings` can decode to
  `[MainShell, Settings]` so back returns to the shell instead of
  exiting the app. `KaiselSingleStackCodec<R>` wraps the v0.1 / v0.2
  `KaiselCodec<R>` for migration without rewriting the codec.
- **Unified `context.router<R>()`.** A new `RouterScope` inherited
  widget exposes whichever `KaiselRouter` is in effect at a point in the
  tree — the flow router inside a modal, the branch router inside a
  shell, the main router elsewhere. `context.branchRouter<R>()` from
  v0.2 still works.
- **`KaiselInnerNavigator<R>` — reusable navigator widget.** The
  "Navigator bound to a KaiselRouter" pattern, exposed as a public
  primitive. Used internally by `KaiselShell` and the modal-flow
  rendering inside `KaiselRouterDelegate`; available for embedding in
  custom router-aware composite widgets.
- **`context.completeFlow<T>(value)` / `context.dismissFlow()`.**
  In-flow accessors for resolving the awaiter on the host router.

### Breaking

- `KaiselRouteInformationParser` now takes a `KaiselStackCodec<R>` and a
  `List<R> fallback`. Migration paths:
  - **Use the new stack codec directly.** Implement `KaiselStackCodec`
    instead of `KaiselCodec`.
  - **Use `.single` named constructor.** Pass your existing
    `KaiselCodec` and a single-route `fallback`:
    `KaiselRouteInformationParser<R>.single(codec: ..., fallback: ...)`.
- The shell context extension is renamed `KaiselBuildContextX` →
  `KaiselShellBuildContextX` to make room for the new unified
  `KaiselRouterContextX` (which provides `context.router<R>()`).
  Method names (`branchRouter`, `shellRouter`) are unchanged, so
  call sites do not need updating.

## 0.2.0 — Guards, equality, and shells

Three additions, one breaking change.

### Added

- **`KaiselGuard<R>` pipeline.** Pass `guards: [...]` to `KaiselRouter` / `ShellRouter` /
  `KaiselShell`. Each guard is `FutureOr<List<R>> Function(current, proposed)`;
  guards run in order, each receiving the previous's output. Return the
  proposed stack unchanged to allow, a different stack to redirect, or
  `current` to refuse. Sync or async — async guards make the navigation
  async, sync guards complete synchronously. Guards do not run on
  navigator-driven pops (system back); they run on `push`/`pop`/`replace`/
  `set`/`popUntil` and on incoming deep links via `setNewRoutePath`.
- **Default `props`-based equality on `KaiselRoute`.** Override `props` with
  the fields you want compared; `==`/`hashCode` come for free. No-field
  variants don't need anything — `Home() == Home()` works out of the box.
  Eliminates the manual equality boilerplate from v0.1 examples.
- **`ShellRouter<R>` and `KaiselShell<R>`.** Multi-branch navigation with
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

- `KaiselRoute` base marker for sealed route types.
- `KaiselRouter<R>` state container with `push`, `pop`, `replace`, `set`, `popUntil`.
- `KaiselRouterDelegate<R>` plugging into `MaterialApp.router`.
- `KaiselRouteInformationParser<R>` for URL → route stack restoration.
- `KaiselCodec<R>` interface for URL ↔ route mapping.
- Identity-stable internal page keying so duplicate equal routes on the stack coexist.
- Pure-Dart unit tests for the navigation state.
