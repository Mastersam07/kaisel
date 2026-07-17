<p align="center">
  <img src="https://raw.githubusercontent.com/Mastersam07/kaisel/dev/assets/brand/kaisel-icon-rounded.png" alt="kaisel" width="110">
</p>

# kaisel_lint
[![codecov](https://codecov.io/github/Mastersam07/kaisel/branch/dev/graph/badge.svg?token=tHYIe4iPGo)](https://codecov.io/github/Mastersam07/kaisel)

Static analysis rules, quick fixes, and assists for the
[kaisel](https://pub.dev/packages/kaisel) Flutter router, built as an
analysis server plugin. Catches bug classes that the type system alone
can't — modal routes pushed onto the main stack, route classes that
forgot value equality, adaptive push calls that should be
pushOrReplaceTop.

## What ships

Six lint rules, four quick fixes, three assists.

### Lint rules

| Rule                                       | Default  | Severity | What it catches                                              |
|:-------------------------------------------|:---------|:---------|:-------------------------------------------------------------|
| `avoid_modal_route_on_main_stack`          | enabled  | warning  | `router.push(modalRoute)` instead of `router.run<T>(modalRoute)` |
| `require_route_props`                      | enabled  | warning  | `KaiselRoute` subclasses with fields but no `props` override |
| `prefer_push_or_replace_top_in_adaptive`   | disabled | info     | `router.push(route)` in projects using adaptive master-detail |
| `prefer_const_route_constructors`          | disabled | info     | a `KaiselRoute` construction that could be `const` but isn't |
| `prefer_pattern_match_over_is_check`       | disabled | info     | `route is SomeRoute` type tests that read better as a `switch` |
| `unused_guard_redirect`                    | disabled | info     | a guard that returns the proposed stack unchanged (a no-op) |

`avoid_modal_route_on_main_stack` and `require_route_props` are the
recommended baseline once the plugin is enabled. The rest are opt-in: the
adaptive rule because we can't statically detect "this code path runs
under an adaptive builder"; `prefer_const_route_constructors` and
`prefer_pattern_match_over_is_check` because they're stylistic
preferences; and `unused_guard_redirect` because the no-op guard it
catches is uncommon (it's cheap insurance against a redirect branch that
silently returns the input unchanged).

### Quick fixes (attached to lint diagnostics)

When a lint fires, the IDE offers a one-click correction:

- `avoid_modal_route_on_main_stack` →  **Convert `push()` to `run<T>()`**
  (the `T` is recovered from the route's `KaiselModalRoute<T>`
  implementation, so the result compiles in one shot).
- `require_route_props` →  **Add `props` override** (generates the list
  from declared instance fields).
- `prefer_push_or_replace_top_in_adaptive` →  **Convert `push()` to
  `pushOrReplaceTop()`**.
- `prefer_const_route_constructors` →  **Add `const`** (inserts the
  keyword, or replaces a leading `new`).

### Assists (cursor-driven, no lint required)

Available from the IDE's refactoring menu whenever the cursor sits on
a qualifying construct, even when the related lint is disabled:

- **Convert `push()` to `run<T>()`** — on any `router.push(modalRoute)`
  call.
- **Add `props` override** — on any `KaiselRoute` subclass (useful
  before adding fields).
- **Convert `push()` to `pushOrReplaceTop()`** — on any
  `router.push(route)` call where the route isn't modal.

## Installation

Add `kaisel_lint` to your `dev_dependencies`:

```yaml
dev_dependencies:
  kaisel_lint: ^0.3.0
```

Then either include the recommended config (activates the plugin with the
correctness baseline on):

```yaml
# analysis_options.yaml
include: package:kaisel_lint/recommended.yaml
```

…or activate it yourself under the `plugins` section (the entry is a map —
`version:` is the pub source, `path:` / `git:` also work):

```yaml
# analysis_options.yaml
plugins:
  kaisel_lint:
    version: ^0.3.0
```

After modifying `analysis_options.yaml`, restart the Dart analysis
server (in VS Code: `Dart: Restart Analysis Server`; in IntelliJ:
File → Invalidate Caches & Restart).

### Enabling and disabling specific rules

Plugin-defined lint rules are off by default until explicitly enabled
under the plugin's `diagnostics` section. To opt in:

```yaml
plugins:
  kaisel_lint:
    version: ^0.3.0
    diagnostics:
      avoid_modal_route_on_main_stack: true
      require_route_props: true
      prefer_push_or_replace_top_in_adaptive: false  # opt-in per project
```

The two strong rules (`avoid_modal_route_on_main_stack` and
`require_route_props`) are the recommended baseline.

### Suppressing individual occurrences

Standard `// ignore` comments work, scoped by the plugin's namespace:

```dart
// ignore: kaisel_lint/avoid_modal_route_on_main_stack
router.push(const AddCardFlow());
```

Use this sparingly — the lints catch real bugs, and ignored occurrences
are easy to forget.

## What the rules catch

### `avoid_modal_route_on_main_stack`

Pushing a `KaiselModalRoute<T>` via `push()` instead of opening it
via `run<T>()` "works" — the page renders — but silently loses the
typed completion contract. The caller of `run<T>` receives a
`Future<T?>` carrying the flow's result; the equivalent doesn't exist
on `push`. False-positive surface is near zero: a route only implements
`KaiselModalRoute<T>` when the author intended it as a flow.

```dart
// Before:
router.push(const AddCardFlow());
// → warning: typed-completion contract is lost

// After (quick fix applied):
router.run<CardId>(const AddCardFlow());
```

### `require_route_props`

`KaiselRoute` subclasses with instance fields must override `props`.
Without value equality, the stack treats two `ProductDetail('a')`
instances as distinct entries — breaking stack diffing,
`pushOrReplaceTop`'s same-type detection, and equality-based
deduplication.

```dart
// Before:
final class ProductDetail extends AppRoute {
  const ProductDetail(this.id);
  final String id;
}

// After (quick fix applied):
final class ProductDetail extends AppRoute {
  const ProductDetail(this.id);
  final String id;

  @override
  List<Object?> get props => [id];
}
```

### `prefer_push_or_replace_top_in_adaptive`

In adaptive master-detail layouts, selecting a different detail with
`push` accumulates duplicates on the stack — list, detail-a, detail-b,
detail-c, … — instead of swapping in place. `pushOrReplaceTop` keeps
the stack two deep regardless of how many times the detail changes.

```dart
// Before:
onTap: () => router.push(ProductDetail(item.id));
// → info: in adaptive context, pushOrReplaceTop swaps in place

// After (quick fix applied):
onTap: () => router.pushOrReplaceTop(ProductDetail(item.id));
```

### `prefer_const_route_constructors`

Routes are value types the stack compares constantly, and `const`
instances are canonicalised so equal routes share identity. This is the
standard `prefer_const_constructors` scoped to `KaiselRoute` subtypes, so
you can enforce const routes without const-ing every class in the
project. It only fires when the construction can actually be const (const
constructor, constant arguments).

```dart
// Before:
final route = ProductDetail('sku-42');
// → info: this KaiselRoute construction can be const

// After (quick fix applied):
final route = const ProductDetail('sku-42');
```

### `prefer_pattern_match_over_is_check`

Routes are sealed value types, so branching on which concrete route is
held reads better as a `switch` — exhaustive, and it destructures fields
without a cast. The rule flags a positive `is` where both the tested
expression and the tested type are `KaiselRoute` subtypes. Capability
checks (`route is KaiselModalRoute`) and `is!` narrowing guards are left
alone.

```dart
// Before:
if (route is Home) return const HomeScreen();
if (route is ProductDetail) return ProductScreen(route.id);
// → info: prefer a pattern match over an is-check on a route

// After (your edit — there is no auto-fix):
return switch (route) {
  Home() => const HomeScreen(),
  ProductDetail(:final id) => ProductScreen(id),
};
```

There's no quick fix: the safe rewrite is contextual — a single check
becomes an `if (route case ...)`, a chain becomes a `switch` — and naively
rebinding the variable can collide with a body-local of the same name.

### `unused_guard_redirect`

A `KaiselGuard` is `(current, proposed) => stack`. One that returns
`proposed` unchanged on every path does nothing — it's either dead code,
or a redirect branch that was meant to return a different stack but
silently returns the input.

```dart
// VIOLATION: a no-op guard.
final guard = (current, proposed) => proposed;

// CORRECT: actually redirects on one path.
final authGuard = (current, proposed) {
  if (!loggedIn) return const [Login()];
  return proposed;
};
```

To stay safe it's conservative: it only fires on a guard-shaped closure
(two `List<R>` parameters) whose body is purely returns and control flow.
A guard kept for a side effect — logging the navigation, say — has another
statement in its body, so it's left alone. There's no quick fix (removing
a guard means editing the `guards:` list).

## Pre-1.0 caveats

- API surface follows kaisel itself: until kaisel v1.0, rules may
  evolve as the library's conventions firm up.
- `prefer_push_or_replace_top_in_adaptive` is **opt-in by design**.
  Whether a push should be `pushOrReplaceTop` depends on runtime layout
  width and the master-detail structure — a per-call decision the
  analyzer can't make for you — so the rule fires on every non-modal
  push. Enable it in projects using adaptive master-detail, where that
  reminder is signal rather than noise.
- Each rule is covered by `AnalysisRuleTest` tests, and every fix and
  assist by end-to-end `PluginServer` tests that apply the change and
  assert the rewritten source.

## Roadmap

The rules originally scoped for the plugin have all shipped. Further rules
track kaisel's own conventions as they firm up toward v1.0.
