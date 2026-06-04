# Adaptive layouts

Reference for `KaiselBranch.adaptive`, `KaiselAdaptivePageBuilder`,
`KaiselAbsorbingPage`, `KaiselStandalonePage`, `KaiselStackContext`,
and `KaiselMasterDetailScaffold`. Use these when the same logical
stack should render differently at different widths — typically a
master-detail layout that's side-by-side on desktop and stacked on
mobile, all driven by the same router state.

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
| `KaiselMasterDetailScaffold` | Convenience side-by-side scaffold for master/detail. |

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
  context.router<ProductRoute>().pushOrReplaceTop(
    ProductDetail(item.id),
  );
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
