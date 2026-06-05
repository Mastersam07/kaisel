# kaisel — monorepo

[![CI](https://github.com/Mastersam07/kaisel/actions/workflows/ci.yml/badge.svg)](https://github.com/Mastersam07/kaisel/actions/workflows/ci.yml)
[![codecov](https://codecov.io/github/Mastersam07/kaisel/branch/dev/graph/badge.svg?token=tHYIe4iPGo)](https://codecov.io/github/Mastersam07/kaisel)

A Dart 3-native Flutter router built on sealed routes, pattern matching, and a stack-as-state model. **No string paths. No codegen.**

This repository is a [pub workspace](https://dart.dev/tools/pub/workspaces) containing the router and its satellite packages.

| Package | Description |
| --- | --- |
| [`packages/kaisel`](packages/kaisel) | The Flutter router — delegate, shells, modules, adaptive layouts, transitions. This is the package you depend on. Start with its [README](packages/kaisel/README.md). |
| [`packages/kaisel_core`](packages/kaisel_core) | Pure-Dart navigation core — sealed routes, the router, guards, and URL codecs. No Flutter dependency. Re-exported by `kaisel`. |
| [`packages/kaisel_devtools`](packages/kaisel_devtools) | DevTools extension for live router inspection. *Scaffold — not yet implemented.* |
| [`packages/kaisel_lint`](packages/kaisel_lint) | Custom lint rules, quick fixes, and assists for the router, built on the first-party `analysis_server_plugin` API. |

## Getting started

Add `kaisel` to your app:

```yaml
dependencies:
  kaisel: ^0.13.0
```

Then see the [`kaisel` README](packages/kaisel/README.md) for the full guide, and [`packages/kaisel/example`](packages/kaisel/example) for runnable examples.

## Migrating from another router

Coming from another router? The [migration guides](packages/kaisel/doc/migration/) cover what translates, what doesn't, and the effort involved:

- [From go_router](packages/kaisel/doc/migration/from-go-router.md)
- [From auto_route](packages/kaisel/doc/migration/from-auto-route.md)

## Editor / AI assistance

This repo ships an [agent skill](skills/kaisel) that teaches AI coding agents how kaisel works — the sealed-route model plus navigation, shells, modal flows, modules, codecs, guards, adaptive layouts, and transitions. Install it with the [`skills` CLI](https://github.com/vercel-labs/skills), which targets Claude Code, Cursor, opencode, and other agents:

```sh
npx skills add Mastersam07/kaisel
```

It lands in your agent's skills directory (e.g. `.claude/skills/`) and loads on the next session — triggering when you work with `package:kaisel` code.

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
