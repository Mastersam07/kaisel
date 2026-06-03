# Roadmap

This document tracks work being considered for future versions of kaisel, and doubles as design notes for contributors. Items are scoped and listed in no particular order; concrete commitment happens only when work begins. The **Design questions** under each item are open for discussion — input via issues or PRs is welcome. Nothing here is a date or a promise.

## 1. State restoration

Flutter's `RestorationManager` / `RestorationMixin` / `restorationId` / `RestorationBucket` mechanism. The OS killing the process and relaunching (common on iOS background-kill, sometimes on Android low-memory) without losing user state.

**Where kaisel stands today.** URL-based restoration works: the codec roundtrips the entire main stack plus shell and module state through `routeInformationProvider`, so an app that's URL-addressable gets effective stack restoration for free. RestorationManager-based restoration doesn't: no `restorationId` on Pages, no `restorationScopeId` on Navigators, no bucket-based stack persistence. For URL-enabled apps the URL covers most needs; for non-URL apps the gap is real.

**Scope, in increasing order of work:**

- **Per-page `restorationId`.** Wrap sites pass `restorationId: 'kaisel-<entryId>'` (or derived from route identity) when constructing Pages. Small mechanical change to four call sites across the delegate and inner navigator. Enables within-page widget state (scroll positions, text controllers via `RestorationMixin`) to survive process death within Pages the Navigator has reconstructed.
- **Navigator `restorationScopeId`.** Add a constructor parameter to `KaiselRouterDelegate` and pass it to the main `Navigator`. Repeat for `KaiselInnerNavigator` so each branch, module, and flow gets its own scope. Lets descendants opt into `RestorationMixin`.
- **Stack persistence via `RestorationBucket`.** Reuse the existing codec layer. The bucket stores the serialized config string; on restore, the same codec deserializes back into a stack. The transport is the only difference from the URL path; the codec interface stays as-is. Sub-routers need independent buckets, coordinated through the existing `KaiselNestedHandle` registration the URL pipeline already uses.

**Design questions.** Opt-in (an explicit `restorable: true` flag on the delegate) or opt-out (default on when a `restorationScopeId` is provided)? How does the bucket interact with guards: are guards re-evaluated during restoration, or is the restored stack trusted? Should branch-level buckets restore independently when the parent shell hasn't restored yet, or wait? These need actual design before implementation.

**Probable home.** v0.13. (a) and (b) are small and can ship together; (c) is the real work and may warrant its own pass.

## 2. Lint package

A separate `kaisel_lint` package using `analysis_server_plugin` to surface common misuses at write time, with quick fixes where possible.

**Rule candidates (initial set; expand as patterns emerge):**

- `prefer_push_or_replace_top_in_adaptive`. When code calls `router.push(X)` and the current top of the router's stack has the same runtime type as `X`, suggest `router.pushOrReplaceTop(X)` instead. This is the bug class the adaptive demo surfaced: pushing `Detail-B` onto a stack with `Detail-A` produces a third entry instead of the in-place swap that adaptive master-detail needs.
- `exhaustive_page_builder`. Warn on a non-exhaustive switch in a `KaiselPageBuilder` or `KaiselAdaptivePageBuilder`. Dart 3 switch expressions already give compile-time exhaustiveness when returning a value, so this is mostly belt-and-suspenders for statement-form switches and helper functions that aren't returning a `Widget` directly.
- `avoid_modal_route_on_main_stack`. Pushing a `KaiselModalRoute` onto the main stack via `push` instead of opening it via `run<T>(...)` is almost always wrong: modal routes are flow entrypoints, not main-stack entries. Quick fix: convert to `run<T>(...)` with a placeholder type argument.
- `unused_guard_redirect`. A guard that takes a stack and returns it unchanged is a no-op. Either drop the guard or make it actually do something. (Has false-positive risk with reflective guards; lint can be off-by-default.)
- `prefer_const_route_constructors`. Routes without instance state should be const-constructed at call sites. Helps the router's stack-diff fast path.

Each rule wants tests under `test/`, a quick fix where applicable, and a sample in the package README. Some rules need cross-file analysis (e.g., to verify a route is a modal route, the analyzer needs to resolve the type's declared interfaces).

**Design questions.** Ship as a separate `kaisel_lint` package or as a sub-package in a kaisel monorepo? Use `custom_lint` (community-friendlier but requires consumers to add a dev dep) or the official `analysis_server_plugin` (heavier integration but ships with the SDK)? Version-locked to `kaisel` or independent?

**Probable home.** Post-state-restoration, since rules can be refined based on patterns that surface as users build real apps with the library. Realistic: v0.14 or later.

## 3. Migration guide from go_router and auto_route

`MIGRATION.md` showing how a typical `go_router` or `auto_route` config translates to kaisel. Side-by-side examples for every common pattern, with honest commentary on what translates cleanly and what doesn't.

**Sections for go_router:**

- Routes table to sealed routes. `GoRoute(path: '/products/:id', ...)` becomes a `sealed class AppRoute` with `Products(id)`.
- Path-first to route-first mental model. `go_router` treats URLs as canonical; kaisel treats routes as canonical and lets the codec produce URLs.
- `redirect` to guards. Different shape: a function from current and proposed stacks to a new stack, instead of a per-route redirect callback.
- `ShellRoute` to `KaiselShell`. Same idea, different boilerplate.
- `StatefulShellRoute` to `KaiselBranchedShell`. The closest 1:1.
- `GoRouterState.of(context)` to `context.router<R>()`. Type parameter is the change.
- Nested navigators to `KaiselInnerNavigator`. More explicit, more typed.

**Sections for auto_route:**

- `@RoutePage()` codegen to manual sealed routes. The big change: no codegen at all.
- Type-safe args. Already free in kaisel via the sealed class constructor; no `RouteParameters` codegen needed.
- `AutoRouter.of(context).push(...)` to `context.router<R>().push(...)`.
- `AutoRouteObserver` to `RouteObserver` attached directly to the Navigator.
- Nested navigation. Same structural answer as for go_router.

**Hard parts to be honest about:**

- kaisel doesn't have a built-in browser-history fine-tuning surface like go_router's. URL state restoration roundtrips entire configs; mid-stack URL changes require manipulating the stack directly.
- kaisel doesn't ship pre-built page transition animations. Users wire them via the v0.11 `pageWrapper` (with the demo as reference).
- Codegen-driven apps will need to manually rewrite routes. Tooling could help (a one-shot conversion script as part of the migration), but that's separate scope.

**Probable home.** Drafted before any "1.0-ready" milestone. Useful at v0.13 or v0.14 to drive realistic try-it-out feedback.

## 4. DevTools extension

A Flutter DevTools extension (via `devtools_extensions` and the post-3.16 extension API) that shows the live state of all routers in a running app. Same shape as Flutter Inspector, scoped to navigation.

**Panels:**

- **Main stack.** Current router stack with route type, params, and entry ID. Updates live as the user navigates.
- **Active branches and module mounts.** Each registered nested host, its stack, and which is currently topmost.
- **Active modal flows.** LIFO list with type, depth, and the awaiter's pending result.
- **Guard trace.** The most recent guard pipeline run, showing each guard's input and output, with the final stack at the bottom. For debugging "why did my navigation get rewritten?"
- **URL preview.** Live render of what URL the current `KaiselConfig` would produce, for testing codec output without leaving DevTools.

**Wiring.** The running app exposes state via the VM service. Two options:

- Register a custom VM service extension (`developer.registerExtension`) that returns a JSON snapshot on request. The extension polls.
- `developer.postEvent` to broadcast state changes. The extension subscribes. Lower-latency, slightly more work.

Either way, the runtime side ships as a small companion package (`kaisel_devtools` or a sub-package) so production builds pay no cost. Probably auto-registered when `kDebugMode` is true.

**Design questions.** Monorepo or separate package? The `devtools_extensions` API is still evolving, so the extension would track Flutter releases. UI is non-trivial and benefits from a designer pass before shipping. Read-only (shows state) or read-write (push/pop routes, replay guard pipelines)? Read-only is the safe first cut.

**Probable home.** v0.15 or later. The runtime hook can land earlier than the UI work.

## Order and dependencies

These are independent tracks. Pick whichever delivers the most value to your current use case:

- Shipping to production where iOS background-kill matters: state restoration first.
- Authoring a lot of code in kaisel and noticing patterns to enforce: lint package.
- Pitching kaisel to a team that currently uses go_router or auto_route: migration guide.
- Debugging gnarly navigation bugs in real apps: DevTools extension.

The roadmap order doesn't imply a release order. v0.13 onwards picks these up as appetite allows.

## Not on the roadmap

- **Code generation.** kaisel is deliberately codegen-free; route definitions stay hand-written. If someone wants `freezed sealed` they already get that via Dart 3 sealed classes plus optional `EquatableMixin` or per-route `freezed`, all without kaisel forcing a build step.
- **Persistence beyond restoration.** Offline mode, sync, or background fetch that touch navigation state are app-level concerns, not router concerns.
- **A pre-built transition animation library.** The v0.11 `pageWrapper` plus `KaiselPageWrapperContext` give users everything needed to write their own. A bundled "common transitions" pack is doable but doesn't earn its way into the core.
- **Built-in analytics hooks.** `RouteObserver` plus standard `ChangeNotifier` listeners cover this without a dedicated API.

This list grows as things crystallize.