# kaisel — monorepo

[![CI](https://github.com/Mastersam07/kaisel/actions/workflows/ci.yml/badge.svg)](https://github.com/Mastersam07/kaisel/actions/workflows/ci.yml)
[![codecov](https://codecov.io/github/mastersam07/gate/branch/dev/graph/badge.svg?token=tHYIe4iPGo)](https://codecov.io/github/mastersam07/gate)

A Dart 3-native Flutter router built on sealed routes, pattern matching, and a stack-as-state model. **No string paths. No codegen.**

This repository is a [pub workspace](https://dart.dev/tools/pub/workspaces) containing the router and its satellite packages.

| Package | Description |
| --- | --- |
| [`packages/kaisel`](packages/kaisel) | The Flutter router — delegate, shells, modules, adaptive layouts, transitions. This is the package you depend on. Start with its [README](packages/kaisel/README.md). |
| [`packages/kaisel_core`](packages/kaisel_core) | Pure-Dart navigation core — sealed routes, the router, guards, and URL codecs. No Flutter dependency. Re-exported by `kaisel`. |
| [`packages/kaisel_devtools`](packages/kaisel_devtools) | DevTools extension for live router inspection. *Scaffold — not yet implemented.* |
| [`packages/kaisel_lint`](packages/kaisel_lint) | Custom lint rules built on the first-party `analysis_server_plugin` API. *Scaffold — no rules yet.* |

## Getting started

Add `kaisel` to your app:

```yaml
dependencies:
  kaisel: ^0.13.0
```

Then see the [`kaisel` README](packages/kaisel/README.md) for the full guide, and [`packages/kaisel/example`](packages/kaisel/example) for runnable examples.

## Working in this repo

```sh
flutter pub get                       # resolves the whole workspace (one lockfile)
dart format --output=none --set-exit-if-changed .
flutter analyze
(cd packages/kaisel_core && dart test)  # pure-Dart core tests
(cd packages/kaisel && flutter test)    # widget-layer tests
```

## Roadmap

See [`packages/kaisel/ROADMAP.md`](packages/kaisel/ROADMAP.md).

## License

[Apache-2.0](LICENSE) © 2026 Codefarmer.
