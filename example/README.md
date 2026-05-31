# gate example

Two entry points, each demonstrating a slice of the library.

## `lib/main.dart`

The main example: bottom-nav `GateBranchedShell` with per-tab typed
routes, modal flows (`router.run<T>(...)`), modules
(`GateModuleMount`), and URL deep-linking via codec.

```sh
flutter run
```

## `lib/main_adaptive.dart`

Adaptive layouts (v0.8+). A book catalogue with master-detail
behaviour at wide widths: detail absorbs list into a side-by-side
layout. The route stack stays the same regardless of width; only
the rendering changes.

```sh
flutter run -t lib/main_adaptive.dart
```

Resize the window past ~700px to see the layout flip between
master-detail and stacked. Selecting a different book at wide
widths does not trigger a Navigator slide (page identity is
preserved via the lowest-absorbed entry's id). The Reviews button
inside the detail pushes a normal stacked page on top regardless
of width.
