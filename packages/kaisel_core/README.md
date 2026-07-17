<p align="center">
  <img src="https://raw.githubusercontent.com/Mastersam07/kaisel/dev/assets/brand/kaisel-mark.png" alt="kaisel" width="110">
</p>

<p align="center">
  <a href="https://codecov.io/github/Mastersam07/kaisel"><img src="https://codecov.io/github/Mastersam07/kaisel/branch/dev/graph/badge.svg?token=tHYIe4iPGo" alt="codecov"></a>
</p>

# kaisel_core

The pure-Dart navigation core for the [`kaisel`](https://pub.dev/packages/kaisel) router. No Flutter dependency.

`kaisel_core` holds the parts of kaisel that don't need widgets:

- **`KaiselRoute`** — the sealed-route base with default `props`-based equality.
- **`KaiselRouter`** — the stack-as-state container (`push`, `pop`, `replaceTop`, `set`, typed main-stack results via `pushForResult<T>`, modal flows via `run<T>`), built on a small pure-Dart change-notifier.
- **`KaiselGuard`** — the composable guard pipeline.
- **URL codecs** — `KaiselCodec`, `KaiselStackCodec`, `KaiselConfigCodec`, `ModuleStackCodec`, and the `KaiselConfig` model.

Because it has no Flutter dependency, this logic is testable with `package:test` alone and usable from non-Flutter Dart.

## Using it

Most apps should depend on **`kaisel`** (the Flutter package), which re-exports everything here plus the widgets:

```yaml
dependencies:
  kaisel: ^1.0.0
```

Depend on `kaisel_core` directly only if you want the navigation logic without Flutter. See the [`kaisel` README](https://github.com/Mastersam07/kaisel/tree/main/packages/kaisel) for the full guide.

> `lib/framework.dart` exposes framework-facing internals to the `kaisel` package. It is **not** part of the public API — application code should not import it.

## License

[Apache-2.0](LICENSE) © 2026 Codefarmer.
