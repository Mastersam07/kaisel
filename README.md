# gate — monorepo

[![CI](https://github.com/Mastersam07/gate/actions/workflows/ci.yml/badge.svg)](https://github.com/Mastersam07/gate/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/Mastersam07/gate/branch/dev/graph/badge.svg?token=tHYIe4iPGo)](https://codecov.io/gh/Mastersam07/gate)

A Dart 3-native Flutter router built on sealed routes, pattern matching, and a stack-as-state model. **No string paths. No codegen.**

This repository is a [pub workspace](https://dart.dev/tools/pub/workspaces) containing the router and its satellite packages.

| Package | Description |
| --- | --- |
| [`packages/gate`](packages/gate) | The Flutter router — delegate, shells, modules, adaptive layouts, transitions. This is the package you depend on. Start with its [README](packages/gate/README.md). |
| [`packages/gate_core`](packages/gate_core) | Pure-Dart navigation core — sealed routes, the router, guards, and URL codecs. No Flutter dependency. Re-exported by `gate`. |
| [`packages/gate_devtools`](packages/gate_devtools) | DevTools extension for live router inspection. *Scaffold — not yet implemented.* |
| [`packages/gate_lint`](packages/gate_lint) | Custom lint rules built on the first-party `analysis_server_plugin` API. *Scaffold — no rules yet.* |

## Getting started

Add `gate` to your app:

```yaml
dependencies:
  gate: ^0.12.0
```

Then see the [`gate` README](packages/gate/README.md) for the full guide, and [`packages/gate/example`](packages/gate/example) for runnable examples.

## Working in this repo

```sh
flutter pub get                       # resolves the whole workspace (one lockfile)
dart format --output=none --set-exit-if-changed .
flutter analyze
(cd packages/gate_core && dart test)  # pure-Dart core tests
(cd packages/gate && flutter test)    # widget-layer tests
```

## Roadmap

See [`packages/gate/ROADMAP.md`](packages/gate/ROADMAP.md).
