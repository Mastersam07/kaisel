---
title: "Migrating from Navigator to kaisel"
editUrl: https://github.com/Mastersam07/kaisel/blob/dev/packages/kaisel/doc/migration/from-navigator.md
---

<!-- Generated from packages/kaisel/doc/migration/from-navigator.md — edit that file, not this one. -->

If you're on Flutter's built-in `Navigator` — imperative `Navigator.push`
with `MaterialPageRoute`, named routes via `MaterialApp(routes:)` /
`onGenerateRoute`, or the declarative Router/Pages API (Navigator 2.0) — this
guide is the practical work of moving to kaisel. It isn't a sales pitch
(that's the [Routes as Values][article] article); it's what translates, what
doesn't, and what your diff will look like.

[article]: https://medium.com/@codefarmer/flutter-routes-as-values-089476ad4d5b

## The short version

`Navigator` is **imperative**: you call `push`/`pop` from anywhere and the
stack is implicit, owned by the framework. Arguments ride along in builder
closures or as an untyped `Object?` in `RouteSettings.arguments`.

kaisel is **value-native**: screens are sealed values, the stack is explicit
state, and a single exhaustive `switch` builds widgets from routes. You stop
constructing `MaterialPageRoute`s and start pushing typed values
(`context.push(Detail(id))`).

The whole migration is that one shift. Everything else — the call sites, the
arguments, the route table — falls out of it mechanically.

(If you hand-rolled **Navigator 2.0** — a `RouterDelegate` plus a `Pages`
list — you've *already* made that shift. Your migration is mostly deletion;
jump to
[Coming from Navigator 2.0](#coming-from-navigator-20-the-routerpages-api).)

## Which Navigator are you using?

There are three on-ramps, and they're not the same effort:

- **Named routes** (`MaterialApp(routes: {...})`, `Navigator.pushNamed`,
  `onGenerateRoute`). You already have a *centralized route table* — the
  thing kaisel wants. Migration is mostly transcribing that table into a
  sealed type and deleting `as`-casts. **This is the gentler path.**
- **Imperative** (`Navigator.push(context, MaterialPageRoute(builder: ...))`
  scattered through the app). No central table exists, so the first job is
  *discovering* every screen and lifting it into the sealed type. A bigger
  conceptual leap, more grep-and-replace.
- **Navigator 2.0** (a hand-rolled `RouterDelegate` + `RouteInformationParser`
  + `Pages` list). You already think declaratively, so the migration is mostly
  *deleting* boilerplate kaisel provides — see
  [Coming from Navigator 2.0](#coming-from-navigator-20-the-routerpages-api).

All three end at the same place — a sealed type, a builder, and a
`KaiselRouterConfig`. The sections below (steps 1–5) are written for the
imperative/named tracks; the Navigator 2.0 section maps the same end state
onto what you'd delete.

## Concept mapping

| Navigator (imperative)                                            | Navigator (named)                                  | kaisel                                              |
| ----------------------------------------------------------------- | -------------------------------------------------- | --------------------------------------------------- |
| `MaterialPageRoute(builder: (_) => DetailScreen())` call sites    | `MaterialApp(routes: {'/detail': ...})`            | a `sealed AppRoute` variant + one `switch` arm      |
| `Navigator.push(ctx, MaterialPageRoute(builder: (_) => Detail(id)))` | `Navigator.pushNamed(ctx, '/detail', arguments: id)` | `context.push(Detail(id))`                           |
| `final args = ModalRoute.of(ctx)!.settings.arguments as DetailArgs` | same                                               | gone — `id` is a typed constructor field            |
| `Navigator.pop(ctx)` / `pop(ctx, result)`                         | same                                               | `context.pop()` / `context.pop(result)`             |
| `await Navigator.push<T>(...)`                                     | `await Navigator.pushNamed<T>(...)`                | `await context.pushForResult<T>(route)`             |
| `Navigator.pushReplacement(...)`                                  | `pushReplacementNamed(...)`                         | `context.replaceTop(route)`                         |
| `Navigator.pushAndRemoveUntil(..., (_) => false)`                 | `pushNamedAndRemoveUntil(..., (_) => false)`       | `context.set([route])`                              |
| `Navigator.popUntil(ctx, predicate)`                              | same                                               | `context.popUntil(predicate)` or `set([...])`       |
| `onGenerateRoute` parsing `/products/42`                          | same                                               | typed construction `Products(42)` — or codec `decode` if it's a real URL |
| `onUnknownRoute`                                                  | same                                               | a `NotFound` route variant + `fallback`             |
| `initialRoute: '/'`                                               | same                                               | `initial: const Home()`                             |
| `showDialog` / `showModalBottomSheet`                             | same                                               | **unchanged** — stay imperative overlays            |
| bottom-nav via `IndexedStack` / per-tab `Navigator`              | same                                               | `KaiselBranchedShell`                               |
| push from a service via a global `navigatorKey`                  | same                                               | `router.push(route)` on a held router reference     |

The left two columns treat a screen as *something you imperatively show*;
the right column treats it as *a value in a stack you mutate*. Everything
cascades from that.

## The migration in five steps

### 1. Define the sealed route type

Enumerate every screen. Each becomes a variant; each push-argument becomes a
typed constructor field.

```dart
sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

final class Home extends AppRoute {
  const Home();
}

final class ProductDetail extends AppRoute {
  const ProductDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id]; // value equality, for free
}
```

- **Named-route track:** your `routes:` map keys and `onGenerateRoute` cases
  *are* this list — transcribe them one-to-one.
- **Imperative track:** grep for `MaterialPageRoute(` and
  `Navigator.push(` to discover the full set. The screens that take
  constructor arguments today keep them; the ones that read
  `settings.arguments` get those arguments promoted to typed fields.

### 2. Write the builder

One exhaustive `switch` from route to widget. This replaces the `routes:`
map, every `onGenerateRoute` case, and every scattered
`MaterialPageRoute(builder:)`.

```dart
Widget buildScreen(BuildContext context, AppRoute route) => switch (route) {
  Home() => const HomeScreen(),
  ProductDetail(:final id) => ProductDetailScreen(id: id),
};
```

The compiler now enforces that every route has a screen — a forgotten one is
a **compile error**, not a runtime "route not found".

### 3. Swap the app root

Replace `MaterialApp(home:/routes:/onGenerateRoute:)` with
`MaterialApp.router` driven by a `KaiselRouterConfig`. Hold the config as a
top-level `final`.

```dart
final _config = KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  builder: buildScreen,
);

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) =>
      MaterialApp.router(routerConfig: _config);
}
```

`initialRoute` becomes `initial:`. `onUnknownRoute` becomes a `NotFound`
variant your builder handles (and, with a codec, the `fallback`).

### 4. Replace the call sites

Mechanical, and grep-able. Push typed values instead of routes/names:

```dart
// before (imperative)
Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetail(id)));
// before (named)
Navigator.pushNamed(context, '/product', arguments: id);

// after
context.push(ProductDetail(id));
```

Then `pop` → `context.pop()`, `pushReplacement(Named)` →
`context.replaceTop(...)`, `pushAndRemoveUntil(..., (_) => false)` →
`context.set([...])`.

**Delete the argument casts.** Every
`ModalRoute.of(context)!.settings.arguments as DetailArgs` goes away — the
screen receives `id` as a typed constructor parameter from the builder.

**Push from outside the widget tree** (a service, a bloc) by holding the
router: `_config.router.push(ProductDetail(id))` — no `navigatorKey` and no
`BuildContext` required.

### 5. Return values, dialogs, tabs

- **A screen that returns a value** (`await Navigator.push<T>` → `pop(result)`)
  becomes `await context.pushForResult<T>(route)`, and the screen returns with
  `context.pop(value)`.
- **Dialogs and bottom sheets stay imperative.** `showDialog` /
  `showModalBottomSheet` work unchanged; `context.pop()` from inside one
  closes it (it's an overlay, not a kaisel route).
- **Bottom-nav / tabs.** An `IndexedStack` or per-tab `Navigator` becomes a
  `KaiselBranchedShell` with one branch per tab — and you get per-tab stack
  preservation as the default.

## What you gain

Coming from `Navigator`, three latent foot-guns disappear at compile time —
this is the reason to migrate, not just the cost:

1. **Typed arguments.** `pushNamed`/`settings.arguments` pass `Object?`; the
   screen casts with `as` (crashes if wrong, silently null if forgotten).
   kaisel arguments are **compile-checked constructor fields** — a whole
   class of "arguments null/wrong-type" bugs is gone.
2. **Exhaustiveness.** A typo'd route string (`'/detial'`) compiles and
   crashes at runtime; a screen you forgot to register is a runtime surprise.
   kaisel's sealed `switch` makes both a **compile error**.
3. **No string drift.** `pushNamed('/detail')` is stringly-typed and drifts
   from its map key. `push(Detail())` is a symbol — rename and refactor
   safely.

You also lose code: the `routes:` map, `onGenerateRoute`/`onUnknownRoute`
plumbing, and every `arguments as X` cast.

## Coming from Navigator 2.0 (the Router/Pages API)

If you hand-rolled a `RouterDelegate` + `RouteInformationParser` + a `Pages`
list, you're already where kaisel wants you: declarative, pages-as-state.
kaisel *is* a typed Navigator 2.0 that owns the machinery you wrote by hand,
so your migration is mostly **deletion**. Steps 1–5 above still land you at
the same place (a sealed type + a builder + a `KaiselRouterConfig`) — but
instead of rewriting call sites, you're throwing boilerplate away.

| Navigator 2.0 (hand-rolled)                                            | kaisel                                          |
| ---------------------------------------------------------------------- | ----------------------------------------------- |
| Custom `RouterDelegate<T>` + `build()` returning `Navigator(pages:)`   | **deleted** — `KaiselRouterDelegate` + your builder `switch` |
| Your nav-state type `T` (the page-list model)                          | a `sealed AppRoute` + the typed stack           |
| `Navigator(pages: [MaterialPage(...), ...])`                           | the stack drives pages; one builder arm per route |
| `onPopPage` / `onDidRemovePage` + the sync dance                       | internal to kaisel                              |
| `ChangeNotifier` + `notifyListeners()` on nav changes                  | `KaiselRouter` *is* the stack-as-state notifier |
| `RouteInformationParser.parseRouteInformation` (URL → `T`)             | `KaiselConfigCodec.decode`                       |
| `restoreRouteInformation` / `currentConfiguration` (`T` → URL)         | `KaiselConfigCodec.encode`                       |
| `setNewRoutePath` / `setInitialRoutePath`                              | `initial:` + codec `decode`                      |
| nested `Navigator`s built in the delegate                              | `KaiselBranchedShell` / modules                 |
| custom `Page` subclasses / bespoke transitions                         | `pageWrapper`                                    |

The win beyond less code: the `onPopPage`/`onDidRemovePage` sync — the part of
Navigator 2.0 everyone gets wrong — disappears, because the stack is the
single source of truth. Your `T` becomes a sealed, exhaustive type, and you
inherit guards, shells, modal flows, and DevTools instead of hand-building
them on your delegate.

**Before** — a hand-rolled delegate (abridged):

```dart
class AppRouterDelegate extends RouterDelegate<AppState>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppState> {
  AppState state = AppState.initial();

  @override
  Widget build(BuildContext context) => Navigator(
    key: navigatorKey,
    pages: [
      const MaterialPage(child: HomeScreen()),
      if (state.productId case final id?)
        MaterialPage(child: ProductDetailScreen(id: id)),
    ],
    onPopPage: (route, result) {
      if (!route.didPop(result)) return false;
      state = state.copyWith(productId: null); // keep this in sync by hand…
      notifyListeners();
      return true;
    },
  );

  @override
  Future<void> setNewRoutePath(AppState configuration) async {
    state = configuration;
  }
  // … plus an AppRouteInformationParser turning the URL into AppState.
}
```

**After** — the delegate, parser, and pop-sync are gone:

```dart
sealed class AppRoute extends KaiselRoute { const AppRoute(); }
final class Home extends AppRoute { const Home(); }
final class ProductDetail extends AppRoute {
  const ProductDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

final _config = KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  builder: (context, route) => switch (route) {
    Home() => const HomeScreen(),
    ProductDetail(:final id) => ProductDetailScreen(id: id),
  },
  // codec: AppCodec(),  // only if those routes were URLs
);
```

Your `AppState` becomes the sealed stack; your parser becomes the codec's
`decode`; your `build` / `onPopPage` / `notifyListeners` become nothing you
maintain. If you were on a Navigator 2.0 *wrapper* (Beamer, Routemaster,
VRouter), you're deleting *their* delegate abstraction instead of your own —
the location/state model still maps onto the codec + stack the same way.

## The one decision that sets the effort

**Did your route names / `onGenerateRoute` strings carry URL or deep-link
meaning, or were they purely internal?**

- **Purely internal** (mobile app, names are just programmatic labels) → the
  strings simply *become types*. No codec needed. The mechanical case.
- **Names were your web URLs / deep links** (or `onGenerateRoute` parsed
  `/products/:id` from a link) → that parsing moves into a kaisel **codec's
  `decode`** so the same URLs keep working. It's the same logic you already
  wrote, relocated and made type-safe. See
  [from-go-router.md](/migration/from-go-router/) §6 for the codec shape.

## What kaisel doesn't yet do at parity

Be honest about these before you start:

- **Browser back integration on the web.** Works via the codec, but value-
  derived URLs are more manual and less battle-tested than a string-path
  router. Test back/forward/refresh on a migration branch if web is the
  primary target.
- **Pre-built page transitions.** No library of named transitions; wire your
  own via the `pageWrapper` mechanism.

## Migration strategy: the main stack flips at once

kaisel owns the app-level `Navigator`, so you can't half-migrate the main
stack — it's a single root swap (step 3). But it isn't all-or-nothing:
`showDialog` / `showModalBottomSheet` and any nested `Navigator` widgets you
embed in your own widgets keep working untouched. Land the sealed type and
builder first (they're additive), then flip the root and replace call sites
in one focused branch.

## A worked example

A small app — Home + ProductList + ProductDetail + Login — typically loses
its `routes:` map, its `arguments as X` casts, and any `onGenerateRoute`
string-parsing, in exchange for one sealed type and one `switch`. The
[`example/`](https://github.com/Mastersam07/kaisel/blob/dev/packages/kaisel/example/) folder demonstrates the same patterns
(branched shells, modal flows, adaptive layouts); scan
[`main.dart`](https://github.com/Mastersam07/kaisel/blob/dev/packages/kaisel/example/lib/main.dart) for a working analogue when a
specific `Navigator` construct is unclear.

## More questions

File an issue at the [kaisel repo][repo] with the `Navigator` pattern you
can't figure out how to translate. Migration-shaped questions are the
highest-value conversations to have right now — they shape what this guide
covers next.

[repo]: https://github.com/Mastersam07/kaisel
