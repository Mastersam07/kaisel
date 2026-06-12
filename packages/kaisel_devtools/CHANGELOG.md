# Changelog

## 0.2.0

### Added

- **Navigation origin in the Transitions log** — each transition now shows the
  app call site that triggered it (the closest frame inline, expandable to the
  full app-frame trace). Every transition in the log keeps its own origin, not
  just the most recent, so you can scroll back and see who issued each
  navigation. Powered by `KaiselRootSnapshot.origin` from `kaisel_core 0.17.0`.

## 0.1.0

- Initial DevTools extension: live navigation snapshots, the main stack with a
  diff highlight, shell branches, modules, flows, guard trace, Problems, the
  Transitions log, the encoded URL with a deep-link decode preview, and the
  read-write command channel.
