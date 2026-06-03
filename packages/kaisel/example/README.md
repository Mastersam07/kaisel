# kaisel example

Five entry points, each demonstrating a slice of the library.
Pick one with `-t`:

| Entry point | What it shows |
| --- | --- |
| `lib/main.dart` | The main example: bottom-nav `KaiselBranchedShell` with per-tab typed routes, modal flows, modules, and URL deep-linking via codec |
| `lib/main_adaptive.dart` | Adaptive layouts at the main delegate (v0.8) with `pushOrReplaceTop` (v0.11) for in-place master-detail swaps |
| `lib/main_shell_adaptive.dart` | Adaptive layout *inside a shell branch* (v0.9): one tab is master-detail, the other isn't, shell stays at the bottom |
| `lib/main_nested_flows.dart` | Nested modal flows (v0.10): a payment flow opens an "add card" flow on top of itself, both layers visible at once |
| `lib/main_transitions.dart` | Route-pair transitions (v0.11): pageWrapper pattern-matches on `(ctx.previous, ctx.route)` to pick custom Page subclasses per route pair |

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
