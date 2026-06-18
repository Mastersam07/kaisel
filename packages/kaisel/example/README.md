# kaisel example

Nine entry points, each demonstrating a slice of the library.
Pick one with `-t`:

| Entry point | What it shows |
| --- | --- |
| `lib/main_inspector.dart` | The **DevTools inspector playground**: one app wiring a branched shell, a checkout module, nested modal flows, redirecting guards, and a full URL codec — driven from a Hub control panel so you can watch every panel of the `kaisel_devtools` extension update live. Its adaptive master-detail **Inbox** demonstrates the missing-`props` bug in situ: open a "Buggy" message, then tap another — the detail pane doesn't change (a `pushOrReplaceTop` no-op), with "Correct" rows beside it for contrast |
| `lib/main_terse.dart` | The terse ergonomics layer: a minimal before/after app wiring `KaiselRouterConfig` into `MaterialApp.router` and navigating with `context.push`/`context.pop` |
| `lib/main.dart` | The main example: bottom-nav `KaiselBranchedShell` with per-tab typed routes, modal flows, modules, and URL deep-linking via codec |
| `lib/main_adaptive.dart` | Adaptive layouts at the main delegate (v0.8) with `pushOrReplaceTop` (v0.11) for in-place master-detail swaps |
| `lib/main_shell_adaptive.dart` | Adaptive layout *inside a shell branch* (v0.9): one tab is master-detail, the other isn't, shell stays at the bottom |
| `lib/main_nested_flows.dart` | Nested modal flows (v0.10): a payment flow opens an "add card" flow on top of itself, both layers visible at once |
| `lib/main_results_and_flows.dart` | Typed results + flows-as-routes (v0.20): `context.pushForResult<T>` returns a value from a main-stack screen; a `run<bool>` flow renders as a route so a `showDialog` lands above it and a shared `RouteObserver` logs the flow's open/close; `pageWrapper` gives the flow a slide-up entrance via `ctx.isFlow` |
| `lib/main_transitions.dart` | Route-pair transitions (v0.11): pageWrapper pattern-matches on `(ctx.previous, ctx.route)` to pick custom Page subclasses per route pair |
| `lib/main_media_cataloguer.dart` | A desktop-style app: top-level auth state machine (`router.set` swaps `LoginRoute` ↔ `ShellHost`), a cross-fade `pageWrapper` between them, a branched shell with per-branch typed routes + nested stacks, and a breadcrumb driven by `KaiselListenableBuilder`. Wired with `KaiselRouterConfig` + `KaiselBranchedShell.specs` + `context.shell()` |

## `lib/main_terse.dart`

The terse ergonomics layer. A minimal before/after app: a top-level
`final KaiselRouterConfig<R>` handed straight to `MaterialApp.router`
(`routerConfig:`) — no `StatefulWidget`, no manual delegate, parser, or
`dispose`. Call sites use the terse `context.*` nav: `context.push(route)`
and `context.pop()`.

```sh
flutter run -t lib/main_terse.dart
```

`KaiselRouterConfig` takes an optional `codec:` for URL deep-linking;
`context.router<R>()` stays available as the typed escape hatch when you
need the router directly.

## `lib/main.dart`

The main example. Bottom-nav `KaiselBranchedShell` with three tabs
(`Home`, `Discover`, `Profile`), each with its own typed sealed
route hierarchy and back stack. Includes a `ConfirmAddToCart` modal
flow (`router.run<bool>(...)`), a `KaiselModuleMount` for the
Checkout module, and URL deep-linking via `KaiselConfigCodec` →
`ConfigCodecWithModules`.

```sh
flutter run
```

## `lib/main_adaptive.dart`

Adaptive layouts (v0.8+). A book catalogue with master-detail at
wide widths: the detail page absorbs the list into a side-by-side
layout. The route stack stays the same regardless of width; only
the rendering changes.

```sh
flutter run -t lib/main_adaptive.dart
```

Resize the window past ~700px to see the layout flip between
master-detail and stacked. Selecting a different book at wide
widths does not trigger a Navigator slide — page identity is
preserved via the lowest-absorbed entry's id, and `pushOrReplaceTop`
(v0.11) keeps the stack at depth 2.

The Reviews button inside the detail pushes a normal stacked page
on top regardless of width.

## `lib/main_shell_adaptive.dart`

Adaptive layouts *inside a shell branch* (v0.9). Two-tab shell:

- **Films** tab uses `KaiselBranch.adaptive` with a master-detail
  builder. Resizing flips this tab's layout between stacked and
  side-by-side.
- **Settings** tab uses a regular `KaiselBranch`. Same layout at all
  widths.

```sh
flutter run -t lib/main_shell_adaptive.dart
```

The bottom nav persists at all widths. Resizing affects only the
Films tab's content area, not the shell chrome.

## `lib/main_nested_flows.dart`

Nested modal flows (v0.10). A payment flow opens an "add card"
flow stacked on top of itself:

1. Tap **Pay** on the home screen → outer `PaymentFlow` opens.
2. Tap **+ Add card** inside the payment flow → inner `AddCardFlow`
   opens on top. Both modal layers are mounted simultaneously.
3. **Save card** inside the inner flow → outer flow's
   `await router.run<String>(AddCardFlow())` resumes with the new
   card.
4. **Pay** inside the outer flow → home's
   `await router.run<bool>(PaymentFlow())` resumes with the result.

```sh
flutter run -t lib/main_nested_flows.dart
```

The outer flow's state (saved cards list) is preserved across the
inner flow opening and closing because the outer modal layer stays
mounted while the inner one renders on top of it.

## `lib/main_transitions.dart`

Route-pair transitions (v0.11). The `pageWrapper` callback
pattern-matches on `(ctx.previous, ctx.route)` to pick a custom
`Page` subclass per route pair:

- **Settings** slides up from the bottom (destination-only).
- **About** fades in (destination-only).
- **Product → Product** (a "Related product" push) cross-fades
  (route-pair).
- Everything else: default Material slide.

```sh
flutter run -t lib/main_transitions.dart
```

The Navigator still drives push/pop direction (forward on add,
reverse on remove). The wrapper picks the transition *style*; the
framework picks the direction.

## `lib/main_results_and_flows.dart`

Typed results and flows-as-routes (v0.20).

```sh
flutter run -t lib/main_results_and_flows.dart
```

"Pick accent colour" calls `context.pushForResult<String>(const ColorPicker())`
— a normal screen on the main stack that returns its value with
`context.pop(value)`. "Edit profile" opens a `run<bool>` modal flow; because a
flow is now a route on the main navigator:

- "Show help" inside the flow opens a `showDialog` that renders **above** the
  flow (the default `useRootNavigator: true` resolves the navigator the flow
  lives on);
- the app's shared `RouteObserver` records the flow's open/close — the
  "Navigation log" panel on Home shows both the picker and the flow boundary.

The `pageWrapper` branches on `ctx.isFlow` to slide the flow up from the bottom
instead of appearing instantly, forwarding `name`/`arguments` so the flow stays
observable.
