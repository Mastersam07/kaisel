# gate_core

The pure-Dart navigation core for the [`gate`](https://pub.dev/packages/gate) router. No Flutter dependency.

`gate_core` holds the parts of gate that don't need widgets:

- **`GateRoute`** — the sealed-route base with default `props`-based equality.
- **`GateRouter`** — the stack-as-state container (`push`, `pop`, `replaceTop`, `set`, modal flows via `run<T>`), built on a small pure-Dart change-notifier.
- **`GateGuard`** — the composable guard pipeline.
- **URL codecs** — `GateCodec`, `GateStackCodec`, `GateConfigCodec`, `ModuleStackCodec`, and the `GateConfig` model.

Because it has no Flutter dependency, this logic is testable with `package:test` alone and usable from non-Flutter Dart.

## Using it

Most apps should depend on **`gate`** (the Flutter package), which re-exports everything here plus the widgets:

```yaml
dependencies:
  gate: ^0.12.0
```

Depend on `gate_core` directly only if you want the navigation logic without Flutter. See the [`gate` README](https://github.com/Mastersam07/gate/tree/main/packages/gate) for the full guide.

> `lib/framework.dart` exposes framework-facing internals to the `gate` package. It is **not** part of the public API — application code should not import it.
