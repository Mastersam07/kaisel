# Adaptive layouts

You want one app that renders as a stacked phone UI on small screens
and as master-detail, multi-pane, or foldable layouts on large ones —
without maintaining a second navigation system.

Reference for `KaiselBranch.adaptive`, `KaiselAdaptivePageBuilder`,
`KaiselAbsorbingPage`, `KaiselStandalonePage`, `KaiselStackContext`,
`KaiselMasterDetailScaffold`, and `KaiselSupportingPaneScaffold`. Use
these when the same logical stack should render differently at different
widths or postures. Master-detail is the common case, but the primitive
(absorption) is layout-agnostic — supporting panes, three-pane, and
foldables are the same mechanism, all driven by the same router state. If you're
looking for **parallel routing** in the multi-pane sense — several routes
rendered on screen at once — this is the guide: one stack, with adjacent
routes absorbed into a single rendered layout.

## The model

A regular `KaiselBranch` calls a `KaiselPageBuilder<R>` that returns a
widget for each route. An adaptive branch calls a
`KaiselAdaptivePageBuilder<R>` that returns a `KaiselPageResult` — and
the result can be either a standalone page (one route, one rendered
page) or an absorbing page (one rendered page that consumes the route
below it).

The key insight: **the router's stack doesn't change between layouts**.
At wide widths, `[List, Detail]` becomes one rendered page laid out
side-by-side. At narrow widths, the same `[List, Detail]` stack renders
as two stacked pages with a slide transition. The route model is
identical; only the rendering layer differs.

## Quick reference

| Type | Purpose |
|:-----|:--------|
| `KaiselAdaptivePageBuilder<R>` | `KaiselPageResult Function(BuildContext, R, KaiselStackContext<R>)` |
| `KaiselPageResult` | Either `KaiselStandalonePage` or `KaiselAbsorbingPage`. |
| `KaiselStandalonePage` | A normal one-route-one-page entry. |
| `KaiselAbsorbingPage` | One page that absorbs `absorbing` entries from below it. |
| `KaiselStackContext<R>` | Context passed to the adaptive builder: `stack`, `position`, plus `previous`, `next`, `isTop`, `isBottom`. |
| `KaiselMasterDetailScaffold` | Convenience side-by-side scaffold for master/detail (small master, large detail). |
| `KaiselSupportingPaneScaffold` | Convenience scaffold for a supporting pane (large primary, small secondary panel on the end). |

## Beyond master-detail

Absorption is layout-agnostic: the widget a `KaiselAbsorbingPage` renders is
yours, and `absorbing: n` can consume more than one entry. The scaffolds are
optional conveniences. The example app shows the range on one primitive:

- **Supporting pane** — `main_supporting_pane.dart` (`KaiselSupportingPaneScaffold`).
- **Three-pane** — same file, `absorbing: 2` with a hand-rolled `Row`.
- **No scaffold at all** — `main_adaptive_stepper.dart`, a wizard that collapses a
  linear stack into a horizontal stepper.
- **Foldables** — `main_foldable.dart`, keyed on `MediaQuery.displayFeatures`
  (fold/hinge) instead of raw width; kaisel collapses the stack, the widget places
  the panes around the hinge.

## The canonical pattern

```dart
KaiselPageResult _productsAdaptiveBuilder(
  BuildContext context,
  ProductRoute route,
  KaiselStackContext<ProductRoute> ctx,
) {
  final isWide = MediaQuery.of(context).size.width >= 700;

  return switch ((ctx.previous, route, isWide)) {
    // The list is always standalone — it can render alone whether or
    // not a detail is on top of it.
    (_, ProductList(), _) =>
      const KaiselStandalonePage(_ProductListScreen()),

    // Detail on top of List at wide widths: collapse the two entries
    // into one rendered page laid out as master-detail. The list pane
    // gets the selected id so it can highlight the active row.
    (ProductList(), ProductDetail(:final id), true) => KaiselAbsorbingPage(
        widget: KaiselMasterDetailScaffold(
          masterFraction: 0.35,
          master: _ProductListScreen(selectedId: id),
          detail: _ProductDetailScreen(id: id, showBack: false),
        ),
        absorbing: 1,  // consumes the ProductList entry below
      ),

    // Detail at narrow widths, or on top of something other than List:
    // standalone, with the normal back button.
    (_, ProductDetail(:final id), _) =>
      KaiselStandalonePage(_ProductDetailScreen(id: id)),
  };
}
```

Then wire it into the branch:

```dart
KaiselBranch<ProductRoute>.adaptive(
  router: _productRouter,
  pageBuilder: _productsAdaptiveBuilder,
)
```

The exhaustiveness of the `switch` is doing real work. Add a new
`ProductRoute` variant and the compiler points at the builder.

## `KaiselStackContext` — pattern matching on neighbours

The adaptive builder receives a `KaiselStackContext<R>` for each entry,
which exposes:

- `stack` — the entire stack as the router has it.
- `position` — this entry's index in the stack (0 is the bottom).
- `previous` — the entry directly below this one (`null` if at the
  bottom).
- `next` — the entry directly above this one (`null` if at the top).
- `isTop` — convenience for `position == stack.length - 1`.
- `isBottom` — convenience for `position == 0`.

Most adaptive builders pattern-match on `(ctx.previous, route, isWide)`
because the absorbing decision depends on what's below: "if the entry
below me is a `List` and I'm a `Detail`, absorb it into a side-by-side
layout." That tuple shape captures the decision exhaustively.

## `pushOrReplaceTop` in adaptive

In an adaptive master-detail, selecting a different list item should
update the right pane in place — not stack another detail. Use
`pushOrReplaceTop`:

```dart
onTap: () {
  context.router<ProductRoute>().pushOrReplaceTop(ProductDetail(item.id));
  // or, terser: context.pushOrReplaceTop(ProductDetail(item.id));
}
```

Without this, every selection adds another detail entry to the stack
(`[List, Detail(a), Detail(b), Detail(c), ...]`). With it, the stack
stays two deep (`[List, Detail(current)]`) and the right pane swaps
on each tap. The visible UX is identical; the stack model is the
difference.

See [NAVIGATION.md](./NAVIGATION.md) for the full distinction between
`push`, `replaceTop`, and `pushOrReplaceTop`.

## `KaiselMasterDetailScaffold`

A convenience widget for the side-by-side layout. Use it inside a
`KaiselAbsorbingPage.widget`:

```dart
KaiselMasterDetailScaffold(
  masterFraction: 0.33,  // default; master gets 1/3 of width
  master: ListView(/* ... */),
  detail: DetailView(/* ... */),
  divider: const VerticalDivider(width: 1),  // optional
)
```

It's flexbox under the hood — master gets `masterFraction` of the row,
detail gets the rest, divider between them. Roll your own if you need
something different (e.g., a fixed-width master or a draggable splitter).

## Two-pane behaviour notes

**The detail pane's "back" affordance.** In a side-by-side layout, the
back button on the detail pane is usually visually wrong — the user
isn't "going back" to anything visible, since the list is right next
to the detail. Set `showBack: false` on the detail screen when it's
rendering inside an absorbing page (the stack still has the list
underneath; the user can pop, just not by tapping a back arrow on the
detail itself).

**Highlighting the selected row.** When the list renders as the master
pane of an absorbed layout, pass the selected detail's identifier so
the list can highlight that row. When it renders standalone (narrow,
or no detail pushed yet), pass `null`. The same `_ProductListScreen`
widget handles both cases via an optional `selectedId` parameter.

**Breakpoint placement.** The 700px breakpoint in the example is a
convention, not a library constraint. Pick what suits the design.
The breakpoint applies to the *content area*, not the screen — if
there's a sidebar taking 100px, account for it.

## Reacting to and guarding detail swaps

A detail swap (`[List, DetailA]` → `[List, DetailB]` via
`pushOrReplaceTop`) is not a pop — and at wide widths it isn't even a
route change: the absorbing page keeps the same Navigator identity and
updates in place. Two consequences:

- **`PopScope` never fires for swaps.** It participates only in pop
  flows (system back / `maybePop`). By design — `canPop: false`
  blocking list selection would break every master-detail.
- **The `Navigator` emits no route events for absorbed changes** —
  push, swap, and pop within the absorbed group all update one page in
  place. kaisel bridges this for the observers registered via
  `observers:` (see below), so screen analytics stay uniform across
  widths.

**Observing changes — `onTransition`.** The router-level callback sees
every committed change as values, at any width:

```dart
KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  builder: ...,
  onTransition: (from, to) {
    // A swap is: same depth, different top.
    ...perform actions
  },
)
```

It fires for push, pop, `replaceTop`, `set`, and system back; not for
no-ops or vetoed navigations. `KaiselRouter` takes the same parameter
directly for routers you construct yourself (shell branches).

**Screen analytics just work.** Observers registered via `observers:`
(e.g. `FirebaseAnalyticsObserver`) receive absorbed in-place changes
kind-matched — growth as `didPush`, shrink as `didPop`, swaps as
`didReplace` — with routes carrying the usual `routeName` and
route-value `arguments`, so everything logs uniformly at every width
with no double events at narrow widths. Resizing across the breakpoint is
not a navigation and reports nothing. Reach for `onTransition` instead
when you want the old and new *stacks* rather than route events.

**Reacting locally.** When DetailA and DetailB render the same screen
widget (the usual `DetailScreen(id:)` shape), the swap is a plain
`didUpdateWidget` — compare `oldWidget.id` to `widget.id`.

**Vetoing a swap (unsaved changes).** Navigation policy belongs in a
guard, which sees every proposed stack including `replaceTop`:

```dart
(current, proposed) =>
    draftService.isDirty ? current : proposed,   // veto while dirty
```

## Shell + adaptive (the combination)

Most apps want adaptive *inside* a branch, not at the top level. The
shell stays at all widths (sidebar or bottom nav); only one branch's
content flips between stacked and side-by-side. Pattern:

```dart
KaiselBranchedShell(
  shell: _shell,
  branches: [
    // Standard branch — no adaptive layout.
    KaiselBranch<HomeRoute>(router: _home, pageBuilder: _homeBuilder),
    // Adaptive branch — master-detail kicks in at wide widths.
    KaiselBranch<ProductRoute>.adaptive(
      router: _products,
      pageBuilder: _productsAdaptiveBuilder,
    ),
  ],
  chromeBuilder: (context, active, content, switchBranch) => /* ... */,
);
```

The shell's bottom nav or sidebar is unaffected by width. The product
branch's content collapses two entries into side-by-side at wide
widths, stacks them with a slide at narrow widths. The same code, the
same stack model, different rendering.

## Common mistakes

| Mistake | Fix |
|:--------|:----|
| Using `push` to select a different detail in adaptive | Use `pushOrReplaceTop`. Otherwise the stack grows on every selection and back has to fire repeatedly to return to the list. |
| Showing the back arrow on the detail pane in absorbed layouts | Pass `showBack: false` (or equivalent) when the detail renders inside an absorbing page. The list is already visible; "back" is visually confusing. |
| Setting the wrong `absorbing` count on `KaiselAbsorbingPage` | `absorbing` defaults to `1` (consume the single entry directly below) — the master-detail case — so omit it there. Set it explicitly only when one rendered page collapses *more than one* entry below it. |
| Pattern-matching only on `route` and `isWide` (ignoring `ctx.previous`) | Absorbing depends on what's below. A `Detail` on top of a `List` absorbs differently than a `Detail` on top of another `Detail`. Match on the triple. |
| Letting the adaptive builder be non-exhaustive | The `switch` should cover every (previous, route, isWide) combination your sealed type can produce. Use `(_, X(), _)` catchalls to keep it exhaustive without listing every cell. |
| Using `MediaQuery.of(context).size.width` when the shell takes meaningful chrome width | Use `LayoutBuilder` inside the branch content to measure the actual available width. MediaQuery is screen-wide. |
