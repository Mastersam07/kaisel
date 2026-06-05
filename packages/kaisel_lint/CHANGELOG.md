# Changelog

## 0.2.0

### Lint rules

- `prefer_const_route_constructors` (info, off by default) — flags a
  `KaiselRoute` construction that could be `const` but isn't. A
  route-scoped variant of `prefer_const_constructors`, so you can enforce
  const routes without const-ing every class in the project.
- `prefer_pattern_match_over_is_check` (info, off by default) — flags
  `route is SomeRoute` type tests (where both sides are `KaiselRoute`
  subtypes), which a `switch`/pattern match expresses better. No quick
  fix — the safe rewrite is contextual.

### Quick fixes

- Add `const` for the const-route lint (inserts the keyword, or replaces
  a leading `new`).

## 0.1.0 — Initial release

First public version. Built as an analysis server plugin on
`analysis_server_plugin: 0.3.7` (analyzer 10.0.1); requires Dart `^3.9.0`.

### Lint rules

- `avoid_modal_route_on_main_stack` (warning, enabled by default) —
  flags `router.push(modalRoute)` where the argument's static type
  implements `KaiselModalRoute<T>`. Pushing a flow loses its typed
  completion contract.
- `require_route_props` (warning, enabled by default) — flags
  `KaiselRoute` subclasses that declare instance fields without
  overriding `props`. Value equality is implicit in the library's
  contract; without `props` the stack treats equal routes as distinct.
- `prefer_push_or_replace_top_in_adaptive` (info, off by default) —
  flags `router.push(route)` calls; opt-in per project where adaptive
  master-detail is in use.

### Quick fixes

- Convert `push()` → `run<T>()` for the modal-route lint, with `T`
  recovered from the route's `KaiselModalRoute<T>` implementation.
- Add `@override List<Object?> get props => [...]` for the props lint,
  generating the list from the class's declared instance fields.
- Convert `push()` → `pushOrReplaceTop()` for the adaptive lint.

### Assists

- Convert `push()` → `run<T>()` (cursor-driven).
- Add `props` override (cursor-driven; usable before adding fields).
- Convert `push()` → `pushOrReplaceTop()` (cursor-driven).
