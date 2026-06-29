# Changelog

## 0.4.0

### Added

- **History disposition in the URL panel** — shows whether the last navigation
  was reported to browser history as a **push** or a **replace** (driven by
  `KaiselRootSnapshot.replacesHistory` from `kaisel_core 0.21.0`), so you can
  see at a glance when a `replaceTop` / `set` / `pop` overwrote the entry
  instead of adding one.

## 0.3.0

### Added

- **Lazy branch build-state in the Branches panel** — a shell branch a lazy
  shell hasn't built yet shows a "not built" tag and "builds on first visit"
  instead of a stack, reflecting the new `built` flag in the navigation
  snapshot. Branches are listed by their real index, so a lazy shell's panel
  stays accurate.

## 0.2.0

### Added

- **Navigation origin in the Transitions log** — each transition now shows the
  app call site that triggered it (the closest frame inline, expandable to the
  full app-frame trace). Every transition in the log keeps its own origin, not
  just the most recent, so you can scroll back and see who issued each
  navigation. **Click a frame to open it in your editor** when DevTools is
  embedded in an IDE (resolves the `package:` URI and posts a navigate event;
  a no-op when no editor is attached). Powered by `KaiselRootSnapshot.origin`
  from `kaisel_core 0.17.0`.

## 0.1.0

- Initial DevTools extension: live navigation snapshots, the main stack with a
  diff highlight, shell branches, modules, flows, guard trace, Problems, the
  Transitions log, the encoded URL with a deep-link decode preview, and the
  read-write command channel.
