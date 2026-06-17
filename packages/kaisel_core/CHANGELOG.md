# Changelog

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
