# Changelog

## 1.0.0

First stable release. The API surface is frozen under semantic versioning:
breaking changes now require a major version and will ship with migration
notes. Functionally identical to 0.23.0 — sealed value routes, the
stack-as-state `KaiselRouter` with guards, typed results, modal flows,
`onTransition`, and the URL codec layer.

## 0.23.0

### Added

- **`KaiselRouter.onTransition`** — an optional callback invoked with the old
  and new stacks (as route values) after every committed change: push, pop,
  `replaceTop`, `set`, and Navigator-driven removals (system back). It does not
  fire for no-op or guard-vetoed navigations. Because the stacks are values, a
  master-detail detail swap is directly detectable
  (`from.length == to.length && from.last != to.last`) — including at wide
  widths, where no Navigator route event exists for observers to see.
  Also available on `KaiselRouter.fromStack`.

## 0.22.0

### Added

- **`KaiselRoute.restorationId`** — a stable id (defaults to `routeName` for
  parameterless routes, `null` for routes with `props`) set as each page's
  `restorationId`, so the page's inner widget state (scroll, text fields via
  `RestorationMixin`) survives process death. Override with a param-aware id
  (e.g. `'product-$id'`) to opt parameterized routes in.

## 0.21.0

### Changed

- **`pop` / `popUntil` add a browser-history entry again, reversing the `0.20.0`
  change ([#27]).** Popping now pushes a new history entry like a normal
  `Navigator` pop instead of overwriting the entry it returns to, so the browser's forward button behaves as expected. History-aligned back navigation that mirrors the app stack moved to the opt-in `context.back()` / `context.historyGo()` in `kaisel`. `replaceTop` / `set` ([#25]) and nested replaces ([#28]) still report a replace.

## 0.20.0

### Added

- **`KaiselRouter.replacesHistoryEntry`** — whether the most recent committed
  stack change should overwrite the browser history entry (`replaceTop` / `set`
  / `pop`) rather than add one (`push`). The Flutter layer's route-information
  provider reads it to report a replace instead of a new entry. ([#25])
- **`KaiselNavigator.replacesHistoryEntry`** and
  **`KaiselNestedHandle.replacesHistoryEntry`** — the same hint on the
  non-generic router view and on a nested handle, so a shell container can read
  its active branch's disposition and the host can report a nested replace as a
  replace. `KaiselNestedHandle` defaults it to `false`. ([#28])
- **`KaiselRootSnapshot.replacesHistory`** — the inspector snapshot now carries
  the last committed change's history disposition (`true` when it overwrote the
  entry rather than added one), so DevTools can show whether a navigation was a
  push or a replace. Defaults to `false`.

### Changed

- **`pop` / `popUntil` now mark the change as a history replace.** Popping back
  to a screen overwrites the entry it returns to instead of adding one, so the
  browser's forward button no longer resurfaces the popped screen. ([#27])

[#25]: https://github.com/Mastersam07/kaisel/issues/25
[#27]: https://github.com/Mastersam07/kaisel/issues/27
[#28]: https://github.com/Mastersam07/kaisel/issues/28

## 0.19.0

### Added

- **`KaiselBranchSnapshot.built`** — the inspector snapshot now reports whether a
  shell branch is materialised, so a lazy shell can show which branches are
  built and which are still dormant. An unbuilt branch carries an empty stack.

## 0.18.0

### Added

- **`pushForResult<T>` — typed results from a main-stack screen.** Push a route
  onto the router's own stack and await a typed value:
  `final r = await router.pushForResult<T>(route)`. The screen returns the value
  by popping with one (`pop(result)`); the future resolves when the pushed entry
  leaves the stack — with the popped value, or `null` if it is popped without
  one, replaced by `set` / `replaceTop`, removed by system back, the router is
  disposed, or a guard prevents it from landing. Unlike `run<T>`, the screen is a
  normal route in the same navigator, so a shared observer sees it and a
  root-navigator dialog renders above it.
- **`pop` now accepts an optional `Object? result`**, delivered to a matching
  `pushForResult` awaiter.

## 0.17.0

### Added

- **Navigation origin tracking** for DevTools. Each committed navigation now
  records the app call site that issued it: `KaiselNavigator` exposes
  `debugLastTransitionOrigin` (the captured `StackTrace`) and a monotonic
  `debugLastTransitionSeq`, and `KaiselRootSnapshot` carries an `origin` list of
  the app frames behind the most recent transition. Two helpers back it —
  `kaiselNextOriginSeq()` and `kaiselOriginFrames()` (trims kaisel, Flutter, and
  SDK frames to the caller) — exposed via `kaisel_core/framework.dart`. Each
  frame is a `KaiselOriginFrame` carrying its display line plus a parsed
  `uri`/`line`/`column` (when locatable), so a DevTools host can open it in an
  editor. Capture is `assert`-gated, so it costs nothing and is null in release.

## 0.16.0

### Changed (breaking)

- **`KaiselRoute.name` → `KaiselRoute.routeName`.** Renamed so the getter can't
  clash with a domain field named `name` (a route may legitimately carry its
  own). If you overrode `name` for a custom screen name, rename the override to
  `routeName`.

## 0.15.0

### Added

- **DevTools read-write surface**, for the kaisel DevTools extension's "drive the
  app" controls: `KaiselInspectable.debugApplyCommand` and an
  `ext.kaisel.command` service extension on `KaiselInspector`.
- **`KaiselRouter.debugHistory`** — a capped, debug-only history of the stacks
  the router has held (real routes), powering DevTools time-travel.
- **`KaiselRootSnapshot.history`** — the stringified history, on the snapshot.
- **`KaiselRoute.name`** — a name for the route (defaults to the runtime type),
  set as `RouteSettings.name` on the page kaisel builds so
  `NavigatorObserver`-based analytics can identify the screen. Override for a
  custom or obfuscation-stable name.

### Changed

- `KaiselInspectable` gains a `debugApplyCommand` member. Breaking only for code
  that implements the (framework-facing) interface directly; the kaisel delegate
  is updated.

## 0.14.0

### Added

- **Debug-only inspector surface**, consumed by the kaisel DevTools extension:
  `KaiselInspector` (a dormant registry) and the `KaiselInspectable` interface,
  plus the renderer-agnostic snapshot model (`KaiselNavSnapshot` and friends).
- **`KaiselRouter` debug fields** for the same: `debugLastGuardRun` /
  `KaiselGuardRun` / `KaiselGuardStep` (guard-pipeline trace), `debugLastNoOp` /
  `KaiselNoOp` (no-op `replaceTop` detection — the missing-`props` symptom), and
  `debugAbsorbedPositions` / `debugSetAbsorbedPositions` (adaptive master-detail
  absorption). All gated so they cost nothing in release.

These are additive; existing APIs are unchanged.

## 0.13.0 — Renamed to kaisel_core

Renamed from `gate_core` to `kaisel_core` as part of the gate → kaisel
rebrand. Mechanical rename, no behavioural change: every `Gate*` type is
now `Kaisel*`, and imports move from `package:gate_core/...` to
`package:kaisel_core/...`. See the
[`kaisel` changelog](https://github.com/Mastersam07/kaisel/blob/main/packages/kaisel/CHANGELOG.md)
for the full migration note.

## 0.12.0

Initial release of `kaisel_core`, extracted from the `kaisel` package as its
pure-Dart navigation core. Contains the sealed-route base, the `KaiselRouter`
stack container (now built on a Flutter-free change-notifier), the guard
pipeline, and the URL codecs — with no Flutter dependency.

Versioned in lockstep with `kaisel`; see the
[`kaisel` changelog](https://github.com/Mastersam07/kaisel/blob/main/packages/kaisel/CHANGELOG.md)
for the history of these APIs prior to the split.
