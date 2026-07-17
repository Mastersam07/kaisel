---
name: kaisel
description: >
  Implement and reason about Flutter routing using the kaisel library — a
  Dart 3-native router built on sealed routes, pattern matching, and a
  stack-as-state model. Use this skill when the user is using or
  considering kaisel, migrating to it from go_router, auto_route, or
  Flutter's Navigator (named, imperative, or 2.0), or when their code
  shows kaisel imports.
  Triggers on: kaisel, KaiselRoute, KaiselRouter, KaiselRouterDelegate,
  KaiselBranchedShell, KaiselBranch, KaiselShell, KaiselPageScope,
  KaiselModalRoute, KaiselConfigCodec, KaiselStackCodec, KaiselGuard,
  KaiselAbsorbingPage, KaiselStandalonePage, KaiselMasterDetailScaffold,
  KaiselPageWrapper, KaiselPageWrapperContext, KaiselStackContext,
  BranchedShellRouter, ShellRouter, RouteModule, ModuleStackCodec,
  package:kaisel, push, pushForResult, pop, back, historyGo, pushOrReplaceTop, replaceTop, set, run,
  pageWrapper, modalBuilder, chromeBuilder, sealed route, codec,
  route guard, modal flow, branched shell, adaptive layout,
  master-detail, route transition, deep link.
---

# kaisel skill

This project uses [kaisel](https://pub.dev/packages/kaisel) — a Flutter
router built on **sealed routes**, **pattern matching**, and a
**stack-as-state** model. No string paths. No code generation.

## The inversion (read this first)

Before any API, the mental model: **sealed routes are the source of truth;
URLs are a serialization layer produced by a codec when needed**. This
inverts the assumption you'd carry over from go_router (paths are
canonical) or from auto_route (annotations generate the typed surface).
In kaisel, the typed `sealed class AppRoute` is primary. URLs come out of
a codec. If you write code that treats URLs as the primary representation,
it will technically work but it will fight the library at every turn —
get this orientation right before reaching for any specific API.

Three things follow from the inversion that are worth internalising:

1. **Routes are data, not behaviour.** A `KaiselRoute` subclass holds
   fields. Equality comes from `props`. No `build` method on the route
   itself; rendering is a separate `pageBuilder` function over the
   sealed type.
2. **The stack is the state.** Auth state, modal state, branch state —
   all expressed as the stack. There's no parallel "is logged in?" flag
   that the router consults; the router's stack either has `LoginRoute`
   or it has `ShellHost` and the cross-fade between them is a
   transition, not a state machine elsewhere.
3. **Exhaustiveness is your friend.** Dart 3's `switch` over a sealed
   type errors at compile time if you forget a variant. Every place that
   handles `AppRoute` — page builders, codecs, transition wrappers —
   gets this guarantee. Lean into it.

## Deep-dive references

Read these only when the topic at hand demands the depth.

| File | When to read |
|:-----|:-------------|
| [NAVIGATION.md](./NAVIGATION.md) | Choosing between `push`, `pushForResult`, `pop`, `back` / `historyGo`, `set`, `replaceTop`, `pushOrReplaceTop`, `run` |
| [SHELLS.md](./SHELLS.md) | Branched shells with per-branch typing; single-branch shells; chrome builders |
| [ADAPTIVE.md](./ADAPTIVE.md) | Adaptive page builders, absorbing pages, master-detail layouts |
| [MODAL_FLOWS.md](./MODAL_FLOWS.md) | Typed modal flows via `router.run<T>(...)`, nested flows, dismissal |
| [TRANSITIONS.md](./TRANSITIONS.md) | Page transitions via `pageWrapper`; route-pair pattern matching |
| [CODEC.md](./CODEC.md) | URL ↔ stack roundtripping; deep linking; browser back |
| [GUARDS.md](./GUARDS.md) | The guard pipeline; auth, feature flags, entitlement gating |
| [MODULES.md](./MODULES.md) | Feature modules, `RouteModule`, modular codec composition |
| [MIGRATION.md](./MIGRATION.md) | Converting an app from go_router, auto_route, or Flutter's Navigator (1.0 / 2.0) |

## Key types

| Type | Purpose |
|:-----|:--------|
| `KaiselRoute` | Base class for every route. Subclasses are sealed data carriers. |
| `KaiselRouterConfig<R>` | A `RouterConfig` bundling router + delegate (+ URL parser/provider when given a `codec`) for `MaterialApp.router(routerConfig:)`. Hold as a top-level `final`; `.router` exposes the bundled `KaiselRouter<R>`. |
| `KaiselRouter<R>` | Holds the stack of routes for type `R`. Mutated via `push`, `pushForResult<T>`, `pop`, `set`, `replaceTop`, `pushOrReplaceTop`, `run<T>`. |
| `KaiselRouterDelegate<R>` | `RouterDelegate` that drives Flutter's `Router` from a `KaiselRouter`. Takes a `builder`, optional `pageWrapper`, optional `modalBuilder`. |
| `KaiselPageBuilder<R>` | `Widget Function(BuildContext, R)`. Pattern-match on the route to produce the screen. |
| `KaiselPageWrapper<R>` | `Page<Object?> Function(KaiselPageWrapperContext<R>)`. Wrap the widget in a `Page` subclass to pick a transition. |
| `KaiselModalBuilder` | Required when using `run<T>`. Describes how a modal flow's UI overlays the main stack. |
| `KaiselGuard<R>` | `FutureOr<List<R>> Function(List<R> current, List<R> proposed)`. Filters every stack mutation. |
| `KaiselConfigCodec<R>` | URL ↔ `KaiselConfig<R>` mapping. The single place strings live. |
| `KaiselBranchedShell` | A shell with N branches, each with its own typed `KaiselRouter`. Per-branch state preserved by default. |
| `KaiselBranch<R>` | One branch inside a `KaiselBranchedShell`. Pass `KaiselBranch.adaptive` for absorbing pages. |
| `KaiselBranchSpec<R>` | Declarative branch for `KaiselBranchedShell.specs`. `lazy: true` builds branches on first visit (kept alive); `KaiselBranchSpec.deferred(loadLibrary:, placeholder:, errorBuilder:)` code-splits a branch behind a `deferred as` import. |
| `KaiselModalRoute<T>` | Abstract base for routes used with `run<T>`. Carries the typed completion contract. |

## 1. Defining routes

```dart
sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

final class Home extends AppRoute {
  const Home();
}

final class ProductList extends AppRoute {
  const ProductList({this.category});
  final String? category;
  @override
  List<Object?> get props => [category];
}

final class ProductDetail extends AppRoute {
  const ProductDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}
```

**Rules:**

- Every route has a `const` constructor when it can. Routes without
  parameters are `const`; routes with parameters are `const` whenever
  their fields are themselves `const`-compatible.
- Override `props` whenever the route has fields. Equality comes from
  `props`; without it, two `ProductDetail('sku-42')` instances are
  unequal and the stack will treat them as distinct entries.
- Sealed type at the root. Pattern matching downstream depends on
  exhaustiveness, which requires the base to be `sealed`.

## 2. Wiring up the router

Hold a `KaiselRouterConfig<R>` as a top-level `final` and hand it
straight to `MaterialApp.router(routerConfig:)`. It bundles the router,
the delegate, and — when you give it a `codec:` — the URL parser and a
`PlatformRouteInformationProvider`. No `StatefulWidget`, no manual
delegate, no hand-rolled parser, no `dispose`.

```dart
final _config = KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  builder: (context, route) => switch (route) {
    Home() => const HomeScreen(),
    ProductList(:final category) => ProductListScreen(category: category),
    ProductDetail(:final id) => ProductDetailScreen(id: id),
  },
  // optional: guards:, pageWrapper:, modalBuilder:, observers:, codec:, fallback:
);

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(routerConfig: _config);
  }
}
```

Omit `codec:` and you get a URL-less, delegate-only app. Pass `codec:`
(plus an optional `fallback:`) and the config wires the
`KaiselRouteInformationParser` and a `PlatformRouteInformationProvider`
for you — the app is URL-addressable. The bundled router is reachable as
`_config.router` (a `KaiselRouter<AppRoute>`) for imperative navigation
outside the widget tree. Call `_config.dispose()` only when a `State`
owns its lifecycle; a top-level `final` lives for the whole app.

For a raw `GlobalKey<NavigatorState>` (a third-party SDK, or `Navigator.of`
overlays without a `BuildContext`), pass `navigatorKey:` to the config or read
`_config.navigatorKey` / `_config.navigator`. For navigation, prefer
`_config.router` — the key is for raw navigator access only.

**Navigator observers.** Pass `observers: () => [MyAnalyticsObserver()]` to
attach `NavigatorObserver`s (analytics, Sentry, `RouteObserver`). It's a
**builder**, not a list: a `NavigatorObserver` belongs to a single
`Navigator`, and kaisel has many — the main stack plus one per shell branch,
module, and active flow — so the builder is called **once per navigator** to
give each its own fresh instance (return new instances each call). That means
one observer per tab in a shell app; for a single unified "current screen"
stream instead, listen to the router(s) directly — the stack is observable
state (`router.addListener(...)`).

Observers read `route.settings.name`; kaisel sets it from each route's
`routeName` getter (defaults to the runtime type, e.g. `'ProductDetail'`; named
`routeName` not `name` to avoid clashing with a domain field) and puts the route
in `settings.arguments`. Override `routeName` with a string **literal** for a
custom screen name — and you must, for stable names under `--obfuscate` (the
runtime type name is minified).

The `switch` is exhaustive. Add a new sealed variant and the compiler
points at every page builder, codec, and transition wrapper that needs
to handle it. That's the type safety the library is designed to give
you in load-bearing form, not just on paper.

**Lower tier — the explicit form.** Constructing a `KaiselRouter`, a
`KaiselRouterDelegate`, and a `KaiselRouteInformationParser` by hand
still works, and is the right tool when a `State` must own each piece's
lifecycle:

```dart
class _AppState extends State<App> {
  late final KaiselRouter<AppRoute> _router;
  late final KaiselRouterDelegate<AppRoute> _delegate;

  @override
  void initState() {
    super.initState();
    _router = KaiselRouter<AppRoute>(initial: const Home());
    _delegate = KaiselRouterDelegate<AppRoute>(
      router: _router,
      builder: (context, route) => switch (route) {
        Home() => const HomeScreen(),
        ProductList(:final category) => ProductListScreen(category: category),
        ProductDetail(:final id) => ProductDetailScreen(id: id),
      },
    );
  }

  @override
  void dispose() {
    _delegate.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerDelegate: _delegate,
      routeInformationParser: _NoopParser(_router),
    );
  }
}
```

## 3. Navigating

The idiomatic default is the typed `context.router<R>()` — the verb is then
compile-checked against the family, so a wrong-family route is a compile
error, and you also get the full `KaiselRouter<R>` surface (`stack`, `pop`,
`run`, …):

```dart
// From any widget inside the delegate's tree:
context.router<AppRoute>().push(const ProductDetail('sku-42'));
context.router<AppRoute>().pop();
context.router<AppRoute>().replaceTop(const ProductList());
context.router<AppRoute>().set(const [Home(), ProductList()]);
final result = await context.router<AppRoute>().run<bool>(const ConfirmFlow());
```

`context.router<R>()` resolves to the nearest enclosing router — the modal
flow's router if inside a flow, the branch's router if inside a shell branch,
otherwise the main router. The type parameter disambiguates which family.

For brevity, the terse `context.*` verbs drop the type parameter:

```dart
context.push(const ProductDetail('sku-42'));
context.pop();
context.pushOrReplaceTop(const ProductDetail('sku-99'));
final quantity = await context.run<int>(const AddCardFlow());
```

These resolve the nearest router whose route type *accepts* the argument by
walking up the tree at runtime. The deliberate trade: a wrong-family route
throws at **runtime** rather than failing to compile — so reach for them when
the terseness clearly earns that trade (a single-router screen, say).
`push`/`pop`/`replaceTop`/`pushOrReplaceTop`/`set` are non-generic; only
`run<T>` carries a result type.

> For decisions between `push`, `replaceTop`, `pushOrReplaceTop`, `set`,
> and `run<T>`, read [NAVIGATION.md](./NAVIGATION.md).

## 4. Parity callout

Be honest about gaps before assuming kaisel can drop into any existing
codebase as a one-for-one replacement.

- **Browser back integration on the web.** Works via the codec, but less
  polished than go_router's native integration. Test on a migration
  branch if web is the primary target.
- **Pre-built page transitions.** No library of named transitions. Wire
  them via the `pageWrapper` mechanism — see
  [TRANSITIONS.md](./TRANSITIONS.md).

See each package's `CHANGELOG.md` for current status.

## 5. Adding a new screen — checklist

1. **Define the route.** Extend the sealed base, add `const` constructor,
   override `props` if it has fields.
2. **Handle it in the page builder.** Add a `switch` arm pattern-matching
   the new variant. The compiler will already be telling you the existing
   builder is non-exhaustive.
3. **Add it to the codec** if the route should be deep-linkable. Update
   both `decode` (URL → route) and `encode` (route → URL). See
   [CODEC.md](./CODEC.md).
4. **Add a guard rule** if access to this screen is conditional. See
   [GUARDS.md](./GUARDS.md).
5. **Custom transition?** Update the `pageWrapper` with a new pattern arm.
   See [TRANSITIONS.md](./TRANSITIONS.md).

## Common mistakes

| Mistake | Fix |
|:--------|:----|
| Forgetting `props` on a route with fields | Override `List<Object?> get props => [...]`. Without it, `ProductDetail('a') != ProductDetail('a')`, breaking equality-based stack operations. |
| Treating `push` of same-type-on-top as the right call in adaptive layouts | Use `pushOrReplaceTop`. Otherwise selecting a different detail stacks duplicates instead of swapping in place. See [ADAPTIVE.md](./ADAPTIVE.md). |
| Pushing a `KaiselModalRoute<T>` onto the main stack via `push` | Use `run<T>(...)`. Pushing it "works" mechanically but loses the typed completion contract. See [MODAL_FLOWS.md](./MODAL_FLOWS.md). |
| Using `is` checks inside a switch arm instead of pattern destructuring | Replace `if (route is ProductDetail) { route.id }` with `case ProductDetail(:final id):`. The compiler enforces exhaustiveness when you do this. |
| Calling `context.router<AppRoute>()` from inside a shell branch and expecting the branch's router | The resolver returns the *nearest* router. From inside a branch, pass the branch's specific type: `context.router<ProductRoute>()`. |
| Holding stale references to routers after the shell disposes | Don't store `KaiselRouter` instances outside their owning `StatefulWidget`'s state. The shell's `dispose` cleans them up; references held elsewhere become stale notifiers. |
| Trying to compose two `MaterialApp.router`s side-by-side to migrate incrementally from another router | Don't. The migration is big-bang. See `packages/kaisel/doc/migration/README.md`. |
