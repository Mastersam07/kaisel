# Migrating to kaisel

Recipe for converting an app from another router or navigation API to kaisel.
This is the **action** reference — do the steps here. The human-facing prose,
effort estimates, and full before/after diffs live in
[`packages/kaisel/doc/migration/`](../../packages/kaisel/doc/migration/); read
the matching `from-*.md` for depth and cite it for the "why".

## 1. Identify the source

| If the code has…                                                        | Source                    | Guide               |
|:------------------------------------------------------------------------|:--------------------------|:--------------------|
| `GoRouter(routes: [GoRoute(path: ...)])`, `context.go/push('/path')`, `redirect:` | **go_router**             | `from-go-router.md` |
| `@RoutePage()`, `*.gr.dart`, `AutoRouterConfig`, `build_runner`         | **auto_route**            | `from-auto-route.md`|
| `MaterialApp(routes:)`, `pushNamed`, `onGenerateRoute`                  | **Navigator (named)**     | `from-navigator.md` |
| `Navigator.push(ctx, MaterialPageRoute(...))` scattered                 | **Navigator (imperative)**| `from-navigator.md` |
| hand-rolled `RouterDelegate` + `RouteInformationParser` + `Pages`       | **Navigator 2.0**         | `from-navigator.md` |

## 2. The target (identical for every source)

Every migration converges on three things:

1. **A sealed route type** — one `final class` per screen; push-arguments
   become typed constructor fields with `props` for value equality.
2. **A builder `switch`** — exhaustive over the sealed type, route → widget.
3. **A `KaiselRouterConfig`** in `MaterialApp.router` — `initial:` + `builder:`
   (+ `codec:` only if URLs / deep links matter).

```dart
sealed class AppRoute extends KaiselRoute { const AppRoute(); }
final class Home extends AppRoute { const Home(); }
final class Detail extends AppRoute {
  const Detail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

final _config = KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  builder: (context, route) => switch (route) {
    Home() => const HomeScreen(),
    Detail(:final id) => DetailScreen(id: id),
  },
);
```

## 3. Source → kaisel mappings

### go_router

| go_router                                  | kaisel                                                  |
|:-------------------------------------------|:--------------------------------------------------------|
| `GoRoute(path: '/products/:id', builder:)` | a sealed variant + `switch` arm; `:id` → constructor field |
| `context.go('/x')`                         | `context.set([...])` or `context.replaceTop(X())`       |
| `context.push('/x')`                       | `context.push(X())`                                     |
| `await context.push<T>('/x')`              | `await context.pushForResult<T>(X())`                   |
| global `redirect:`                         | a guard in the pipeline (`GUARDS.md`)                   |
| `ShellRoute` / `StatefulShellRoute`        | `KaiselBranchedShell` (`SHELLS.md`)                    |
| path patterns / `parseRouteInformation`    | `KaiselConfigCodec.decode` (`CODEC.md`)                |

### auto_route

| auto_route                          | kaisel                                                       |
|:------------------------------------|:-------------------------------------------------------------|
| `@RoutePage()` widget               | a sealed variant + `switch` arm (delete the annotation + `.gr.dart`) |
| generated `XRoute(args)`            | an `X(args)` value                                          |
| `context.router.push(XRoute())`     | `context.push(X())`                                        |
| `AutoRouteGuard`                    | a guard function in the pipeline (`GUARDS.md`)             |
| `AutoTabsScaffold` / `AutoTabsRouter` | `KaiselBranchedShell` (`SHELLS.md`)                      |
| `build_runner`                      | gone — no codegen                                           |

### Navigator (imperative / named / 2.0)

| Navigator                                                                   | kaisel                                           |
|:----------------------------------------------------------------------------|:-------------------------------------------------|
| `Navigator.push(ctx, MaterialPageRoute(builder: (_) => X(id)))` · `pushNamed('/x', arguments: id)` | `context.push(X(id))`                            |
| `pop` · `pop(result)`                                                       | `context.pop()` · `context.pop(result)`          |
| `await Navigator.push<T>(...)`                                              | `await context.pushForResult<T>(X())`            |
| `pushReplacement(Named)`                                                    | `context.replaceTop(X())`                        |
| `pushAndRemoveUntil(..., (_) => false)`                                     | `context.set([X()])`                             |
| `settings.arguments as XArgs`                                              | typed constructor fields — delete the cast       |
| hand-rolled `RouterDelegate` / `onPopPage` / parser (2.0)                   | **delete** — kaisel provides it; parser → codec  |
| `IndexedStack` / per-tab `Navigator`                                        | `KaiselBranchedShell`                            |

## 4. Pitfalls — get these right

- **Never push a raw `MaterialPageRoute` / `Page` onto kaisel's main
  navigator.** The router stack is the single source of truth — push kaisel
  routes. Imperative routes desync the declarative `pages` list.
- **`showDialog` / `showModalBottomSheet` stay imperative** and unchanged.
  `context.pop()` from inside one closes it. Don't convert dialogs to routes
  unless they're genuinely full screens.
- **Imperative interop via a global `navigatorKey`:** the key you hand kaisel
  is the **declarative main navigator**. `showDialog` defaults
  `useRootNavigator: true` while `Navigator.pop` defaults
  `rootNavigator: false` — under `MaterialApp.router` both resolve to the same
  navigator, but inserting any navigator layer above splits them (dialog goes
  up, pop hits the page behind). Prefer the modal page's own `context`, or hold
  the router for context-free nav (`config.router.push(...)`).
- **Codec round-trip is a foot-gun.** `encode` is exhaustive (sealed routes);
  `decode` (string → route) is **not**. A missing or typo'd `decode` arm = a
  silently broken Back button. Always add a round-trip test and a `NotFound`
  `_ =>` arm plus `fallback`.
- **A codec is optional.** A pure mobile app with no URLs / deep links skips
  the codec entirely.
- **Translate, don't invent.** `redirect` / guard classes → the guard
  pipeline; tab scaffolds → branched shells; path params → typed fields. Don't
  reach for string paths — kaisel is value-native by design.
- **Arguments become typed fields, not `Object?`.** Delete every `as XArgs`
  cast; the builder hands the screen typed constructor parameters.

## 5. Verify (run after migrating)

- [ ] The `builder` `switch` is **exhaustive** — it compiles with **no** `_ =>`
      fallback (the compiler proves every screen is handled).
- [ ] App builds; `flutter analyze` is clean.
- [ ] If a codec exists: it **round-trips** — for representative routes,
      `decode(encode(config))` reproduces the stack (write a unit test).
- [ ] Deep links and browser back/forward/refresh land on the right stack
      (only if web / deep linking matters).
- [ ] Dialogs and bottom sheets still open and dismiss (`context.pop()` from
      inside closes them).
- [ ] Per-tab state survives tab switches (a branched shell preserves it by
      default).
- [ ] No raw `Navigator.push(MaterialPageRoute(...))` left on the main stack
      (grep for it).

## Worked examples

For full before/after diffs and effort estimates, read the matching guide:

- [from-go-router.md](../../packages/kaisel/doc/migration/from-go-router.md)
- [from-auto-route.md](../../packages/kaisel/doc/migration/from-auto-route.md)
- [from-navigator.md](../../packages/kaisel/doc/migration/from-navigator.md)
