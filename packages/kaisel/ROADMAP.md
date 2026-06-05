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

**Probable home.** A future minor release. (a) and (b) are small and can ship together; (c) is the real work and may warrant its own pass.

## 2. DevTools extension

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
- Debugging gnarly navigation bugs in real apps: DevTools extension.

The roadmap order doesn't imply a release order. v0.13 onwards picks these up as appetite allows.

## Not on the roadmap

- **Code generation.** kaisel is deliberately codegen-free; route definitions stay hand-written. If someone wants `freezed sealed` they already get that via Dart 3 sealed classes plus optional `EquatableMixin` or per-route `freezed`, all without kaisel forcing a build step.
- **Persistence beyond restoration.** Offline mode, sync, or background fetch that touch navigation state are app-level concerns, not router concerns.
- **A pre-built transition animation library.** The v0.11 `pageWrapper` plus `KaiselPageWrapperContext` give users everything needed to write their own. A bundled "common transitions" pack is doable but doesn't earn its way into the core.
- **Built-in analytics hooks.** `RouteObserver` plus standard `ChangeNotifier` listeners cover this without a dedicated API.
- **Automatic adaptive replace-top.** In adaptive master-detail, pushing a same-type detail onto another stacks a duplicate instead of swapping in place; the answer is to call `pushOrReplaceTop` rather than `push`. Making that automatic — via a route marker, or a router/branch mode that auto-replaces — was considered and rejected. The router is pure-Dart and width-agnostic, so it can't know it's in an adaptive context; the only places to put the behavior either couple navigation policy onto route data or make `push` implicitly conditional, both of which trade away the per-call control and explicitness kaisel optimizes for. `push` vs `pushOrReplaceTop` stays an explicit, per-call choice.

This list grows as things crystallize.