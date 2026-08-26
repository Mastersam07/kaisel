# Migrating from auto_route to kaisel

If you're reading this, you've already decided — or mostly decided — that
you want to move. This guide tells you what that actually looks like. It
isn't a sales pitch for kaisel (that's the [Routes as Values][1] article)
and it isn't a list of grievances against auto_route. It's the practical
work: what translates one-to-one, what doesn't, and what the diff against
your existing codebase will look like.

[1]: https://medium.com/@codefarmer/flutter-routes-as-values-089476ad4d5b

## The short version

auto_route already thinks in typed routes. You're not changing your mental
model — you're removing the layer that produced those types via code
generation and writing them by hand instead. The compiler does the same
work, just without a build step.

The migration is mechanical for most of your routes. The conceptual work
is concentrated in two places: guards (auto_route's `AutoRouteGuard`
becomes a pipeline function in kaisel) and tabbed shells (`AutoTabsScaffold`
becomes `KaiselBranchedShell`, with state preservation already on by
default rather than opt-in via stateful variants).

For an app of about thirty screens with a couple of guards and one tabbed
shell, plan two days. Most of that is mechanical translation; the slow
part is testing that nothing regressed.

## Concept mapping

| auto_route                                  | kaisel                                            |
| ------------------------------------------- | ------------------------------------------------- |
| `@RoutePage()` annotation                   | `final class Home extends AppRoute`               |
| Codegen-produced `HomeRoute()` class        | Hand-written class with `const` constructor       |
| `@AutoRouterConfig` with `AutoRoute(...)`s  | A single `switch` expression in a page builder    |
| `final _appRouter = AppRouter()` + `routerConfig:` | `final _config = KaiselRouterConfig<AppRoute>(...)` + `routerConfig:` |
| `AutoRouteGuard.onNavigation()`             | Guard function `(current, proposed) → stack` in the pipeline |
| `AutoTabsScaffold`                          | `KaiselBranchedShell.specs` with N branches (`lazy: true` for lazy-loaded tabs; `KaiselBranchSpec.deferred` to code-split one) |
| Parent route with `children: [...]`         | Stack entries; sub-routers if you need isolation  |
| `context.router.push(HomeRoute())`          | `context.push(const Home())`                      |
| `await context.router.push<T>(EditRoute())` (returns a value) | `await context.pushForResult<T>(const Edit())` — resolved with `context.pop(value)` |
| `context.router.pop()`                      | `context.pop()`                                   |
| `context.router.replaceAll([HomeRoute()])`  | `context.set([const Home()])`                     |
| `defaultRouteParser()`                      | A `KaiselConfigCodec<AppRoute>` you write         |
| `build_runner` step in CI                   | (gone)                                            |

The biggest material difference in your day-to-day workflow is the last
row. No more `dart run build_runner watch`, no more "why didn't my
generated files update," no more committing `*.gr.dart` to git or
gitignoring them. Pubspec gets shorter, CI gets faster.

## The migration in five steps

### 1. Project setup

In `pubspec.yaml`, swap auto_route for kaisel:

```diff
 dependencies:
   flutter:
     sdk: flutter
-  auto_route: ^9.0.0
+  kaisel: ^1.0.0

 dev_dependencies:
-  auto_route_generator: ^9.0.0
-  build_runner: ^2.4.0
```

If `build_runner` is being used solely for auto_route, drop it. If
other packages depend on it (json_serializable, freezed, etc.), keep
it but you'll no longer rebuild on every route change.

Delete every `*.gr.dart` file. They'll be recreated as hand-written
classes in step 2.

Then replace the router instance. auto_route gives `MaterialApp.router`
a `routerConfig:` (or `routerDelegate:` + `routeInformationParser:`)
from a generated `AppRouter`. kaisel has the same slot: a top-level
`final _config = KaiselRouterConfig<AppRoute>(...)`.

**Before** (auto_route):

```dart
final _appRouter = AppRouter();

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) =>
      MaterialApp.router(routerConfig: _appRouter.config());
}
```

**After** (kaisel):

```dart
final _config = KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  builder: (context, route) => switch (route) {
    Home() => const HomeScreen(),
    ProductList() => const ProductListScreen(),
    ProductDetail(:final id) => ProductDetailScreen(id: id),
  },
  // optional: guards:, pageWrapper:, modalBuilder:, codec:, fallback:
);

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) =>
      MaterialApp.router(routerConfig: _config);
}
```

`KaiselRouterConfig` is app-lifetime: a top-level `final`, no
`StatefulWidget`, no manual `KaiselRouterDelegate`, no hand-rolled
parser. Omit `codec:` and the app is URL-less; pass `codec:` (and
optionally `fallback:`) to make it URL-addressable — it wires the
parser and `PlatformRouteInformationProvider` for you (step 6).
`_config.router` exposes the bundled `KaiselRouter` if you need
imperative access. The explicit delegate-plus-parser form remains
available as a lower tier.

### 2. Translate `@RoutePage` widgets to sealed routes

For each annotated screen, you produce two things: a sealed route
class for the destination, and an unchanged screen widget. The screen
loses its annotation.

**Before** (auto_route):

```dart
@RoutePage()
class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, @PathParam('id') required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    // ... unchanged
  }
}
```

**After** (kaisel):

```dart
final class ProductDetail extends AppRoute {
  const ProductDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    // ... unchanged
  }
}
```

Two things to notice. First, the route class and the screen widget
are now separate — the screen takes its parameter directly, no
`@PathParam` annotation. Second, `props` overrides give the route
value equality so two `ProductDetail('sku-42')` instances are equal
to each other (matters for stack diffing).

**Routes that carried callbacks.** A closure field breaks both `const`-ness
and value equality, so `onComplete` / `onClose` / `onAction` can't travel on a
kaisel route. Move the behaviour to the page builder, which has the router in
scope, and turn the callback into a result:

```dart
// route carries data only; the builder wires the behaviour
EddFlow(:final type) => EddFlowPage(type: type, onComplete: router.pop),
```

That works, but a bare `pop()` is indistinguishable from the user backing out
— both arrive as `null` at `pushForResult`. When the caller needs to tell
"completed" from "dismissed", either pop an explicit value
(`onComplete: () => router.pop(true)`) or — for a multi-step sub-experience —
reach for [`run<T>`](/guides/modal-flows/) with a `KaiselModalRoute<T>`, whose
typed completion contract exists for exactly this conversion.

**Parameters inherited from a parent router.** auto_route lets a nested child
read a path parameter declared on its parent via
`@PathParam.inherit('countryCode')`, resolved from the URL at build time — so
the child's generated args class never carries it. kaisel routes are explicit
data with no inheritance: the child must declare the field itself, which also
means **every construction site for that route gains an argument**.

```dart
final class BillProvider extends AppRoute {
  const BillProvider({required this.countryCode, required this.providerId});
  final String countryCode;
  final String providerId;
  @override
  List<Object?> get props => [countryCode, providerId];
}
```

The change is mechanical but nothing in the type system points at it — a naive
port compiles and then has no idea what country it is for. Grep for
`PathParam.inherit` before you start; each hit is a field to add and a set of
call sites to update.

Group your routes into a single sealed hierarchy:

```dart
sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

final class Home extends AppRoute {
  const Home();
}

final class ProductList extends AppRoute {
  const ProductList();
}

final class ProductDetail extends AppRoute {
  const ProductDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}
```

### 3. Replace AutoRouterConfig with a page builder

auto_route's route table — the giant list of `AutoRoute(page: ..., ...)`
entries — becomes a single `switch` expression in the `builder:` of
your `KaiselRouterConfig` (the one from step 1).

**Before** (auto_route):

```dart
@AutoRouterConfig()
class AppRouter extends $AppRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: HomeRoute.page, path: '/'),
    AutoRoute(page: ProductListRoute.page, path: '/products'),
    AutoRoute(page: ProductDetailRoute.page, path: '/products/:id'),
  ];
}
```

**After** (kaisel):

```dart
final _config = KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  builder: (context, route) => switch (route) {
    Home() => const HomeScreen(),
    ProductList() => const ProductListScreen(),
    ProductDetail(:final id) => ProductDetailScreen(id: id),
  },
);
```

The `switch` is exhaustive — the Dart 3 compiler errors if you add a
new route variant and forget to handle it here. Path strings move
into the codec (step 6), not the page builder.

### 4. Translate guards

`AutoRouteGuard` is a class with `onNavigation(resolver, router)`. The
kaisel equivalent is a pure function that takes the proposed stack
and returns the actual stack — same conceptual job, different shape.

**Before** (auto_route):

```dart
class AuthGuard extends AutoRouteGuard {
  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    if (isLoggedIn) {
      resolver.next(true);
    } else {
      router.push(LoginRoute(onResult: (success) {
        resolver.next(success);
      }));
    }
  }
}

// Attached to a route:
AutoRoute(page: ProfileRoute.page, guards: [AuthGuard()]),
```

**After** (kaisel):

```dart
List<AppRoute> authGuard(List<AppRoute> current, List<AppRoute> proposed) {
  // Requires login for any Profile-like route.
  final wantsAuthScreen = proposed.any((r) => r is Profile);
  if (wantsAuthScreen && !isLoggedIn) {
    return [const Login()];
  }
  return proposed;
}

// Registered once on the config, applies to all mutations:
final _config = KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  builder: (context, route) => switch (route) { /* ... */ },
  guards: [authGuard],
);
```

Two notes on this translation. First, the guard runs against every
stack mutation, not just push — so `router.set([...])` and
`router.replaceTop(...)` are also guarded. With auto_route's
per-route attachment, you had to remember to attach the guard to
every gated screen. Second, the guard returns a stack, not a
"redirect URL" — so a guard can do things go_router-style redirects
can't, like injecting a step into a stack rather than replacing it
wholesale.

auto_route's `LoginRoute(onResult: ...)` — push a screen and await its result —
maps to `await context.pushForResult<bool>(const Login())`, with the login screen
calling `context.pop(true)`. And to **redirect to login and then continue** to the
route the user was headed for, stash the `proposed` stack in the guard and replay
it with `context.set(...)` after login — the intended destination is plain
`List<AppRoute>` data (see `example/lib/main_auth_redirect.dart`).

For multiple cross-cutting concerns (auth + feature flags + entitlement
checks), compose them as a list of guards rather than nesting:

```dart
KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  builder: (context, route) => switch (route) { /* ... */ },
  guards: [authGuard, featureFlagGuard, entitlementGuard],
)
```

Each runs in order. Each receives the output of the previous.

### 5. Replace AutoTabsScaffold with KaiselBranchedShell

If your app has a tabbed shell, this is where most of the rewrite
happens. `AutoTabsScaffold` becomes `KaiselBranchedShell.specs`, and
each tab gets its own sealed route type for per-branch typing.

**Before** (auto_route):

```dart
@RoutePage()
class MainScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AutoTabsScaffold(
      routes: const [
        HomeTabRoute(),
        ProductsTabRoute(),
        SettingsTabRoute(),
      ],
      bottomNavigationBuilder: (_, tabsRouter) => BottomNavigationBar(
        currentIndex: tabsRouter.activeIndex,
        onTap: tabsRouter.setActiveIndex,
        items: const [/* ... */],
      ),
    );
  }
}
```

**After** (kaisel):

```dart
sealed class HomeRoute extends KaiselRoute { const HomeRoute(); }
final class HomeView extends HomeRoute { const HomeView(); }

sealed class ProductRoute extends KaiselRoute { const ProductRoute(); }
final class ProductList extends ProductRoute { const ProductList(); }
final class ProductDetail extends ProductRoute {
  const ProductDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

sealed class SettingsRoute extends KaiselRoute { const SettingsRoute(); }
final class SettingsView extends SettingsRoute { const SettingsView(); }

// The shell owns the per-branch routers — no manual KaiselRouter to wire.
KaiselBranchedShell.specs(
  branches: [
    KaiselBranchSpec<HomeRoute>(
      initial: const HomeView(),
      builder: (c, r) => switch (r) {
        HomeView() => const HomeTabScreen(),
      },
    ),
    KaiselBranchSpec<ProductRoute>(
      initial: const ProductList(),
      builder: (c, r) => switch (r) {
        ProductList() => const ProductListScreen(),
        ProductDetail(:final id) => ProductDetailScreen(id: id),
      },
    ),
    KaiselBranchSpec<SettingsRoute>(
      initial: const SettingsView(),
      builder: (c, r) => switch (r) {
        SettingsView() => const SettingsScreen(),
      },
    ),
  ],
  chromeBuilder: (context, activeBranch, branchContent, switchBranch) => Scaffold(
    body: branchContent,
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: activeBranch,
      onTap: switchBranch,
      items: const [/* ... */],
    ),
  ),
);
```

`KaiselBranchedShell.specs` declares each branch's initial route and
builder, and the shell owns the per-branch routers — no
`StatefulWidget`, no manual `KaiselRouter` or `BranchedShellRouter`.
(The explicit `KaiselBranchedShell(shell:, branches: [KaiselBranch(...)])`
form stays available as the lower tier if you need to hold the routers
yourself.)

The notable thing is per-branch typing. Each `KaiselBranchSpec` takes
a specific sealed type — `KaiselBranchSpec<HomeRoute>`, not a single
shared `AppRoute` — so its router is typed too. The compiler will
reject pushing a `ProductDetail` into the home branch as a type error.
That's the type safety the article talks about becoming load-bearing
in your editor, not just on paper. From inside a branch, reach the
shell with `context.shell()` (a `KaiselShellController`: `.switchTo(i)`,
`.activeBranch`, `.branchCount`, `.current`).

State preservation across tab switches is on by default — you don't
need a stateful variant the way auto_route does.

### 6. Wire up the codec (only if you need deep linking)

If your app uses deep links, browser-friendly URLs, or web routing,
write a codec. If it doesn't, skip this step and use a no-op parser.

```dart
class AppCodec extends KaiselConfigCodec<AppRoute> {
  @override
  KaiselConfig<AppRoute> decode(Uri uri) {
    return switch (uri.pathSegments) {
      [] || ['home'] => KaiselConfig(mainStack: [const Home()]),
      ['products'] => KaiselConfig(mainStack: [const Home(), const ProductList()]),
      ['products', final id] => KaiselConfig(
        mainStack: [const Home(), const ProductList(), ProductDetail(id)],
      ),
      _ => KaiselConfig(mainStack: [const Home()]),  // fallback
    };
  }

  @override
  Uri encode(KaiselConfig<AppRoute> config) {
    final top = config.mainStack.last;
    return switch (top) {
      Home() => Uri(path: '/home'),
      ProductList() => Uri(path: '/products'),
      ProductDetail(:final id) => Uri(path: '/products/$id'),
    };
  }
}
```

The codec is the only place strings live. Every other layer reasons
about typed routes.

## Verb translation

The full navigation surface, since a real migration touches far more than the
concept mapping above. (One port measured 787 router calls across 41 files.)

| auto_route | kaisel |
| --- | --- |
| `push(X)` | `push(X)` |
| `push<T>(X)` (awaited) | `pushForResult<T>(X)` |
| `navigate(X)` | `push(X)` |
| `replace(X)` | `replaceTop(X)` |
| `replaceAll([...])` | `set([...])` |
| `popAndPush(X)` | `replaceTop(X)` |
| `pop()` | `pop()` |
| `pop<T>(result)` | `pop(result)` — the result is `Object?`, so the type is not checked against the awaiting `pushForResult<T>` |
| `maybePop()` | `context.maybePop()` — **not** `pop()`; see below |
| `pushAndPopUntil(X, predicate:)` | `pushAndPopUntil(X, predicate:)` |
| `popUntilRouteWithName(n)` | `popUntil((route) => route is N)` |
| `popUntilRoot()` | `popUntilRoot()` |
| `router.root` / `router.parent` | n/a — the stack is flat |
| `router.stackData` | `router.stack` |
| `entry.routeData` | the entry **is** the route |
| `entry.routeData.args` | destructure the route: `Product(:final id)` |
| `route.settings.name == X.name` | `route is X` — see below |
| `isRouteActive(X.name)` | `stack.any((route) => route is X)` |

### Two rows that bite

**`maybePop()` → `pop()` is wrong.** It is the most natural-looking
translation and it silently changes behaviour: `pop()` mutates the kaisel
stack directly, so an open `Drawer`'s local history entry is never consumed
and a `PopScope(canPop: false)` veto is never consulted. Use
`context.maybePop()`, which asks the `Navigator` first. In one migration
`maybePop` was 155 of 170 pop-family calls — this is the common case, not an
edge one.

**`route.settings.name == X.name` → `route is X`.** Rewriting `.name`
mechanically produces `route == BuyRoute` — comparing a `String` to a
`Type`. That **compiles**; only `unrelated_type_equality_checks`, an
*info*-level lint, catches it. Left alone it ships as a permanently-false
condition. Pattern-match on the type instead.

## Nested router shells (`AutoRouter` parents with `children:`)

The shape that dominates any non-trivial auto_route app:

```dart
AutoRoute(
  path: '/bills',
  page: BillRouterRoute.page,        // class BillRouterPage extends AutoRouter
  children: [
    AutoRoute(page: BillListRoute.page, initial: true),
    AutoRoute(page: BillDetailRoute.page),
  ],
),
```

The parent renders no UI of its own — it exists to host a nested navigator.
kaisel's stack is flat, so there is no direct analogue, and this is usually
the largest structural decision in a port. Pick by asking **what the nesting
was buying you**:

### 1. Nothing but organisation → flatten it

The common case. If the parent is a bare `AutoRouter` and the children are
ordinary screens, the nesting was a routing-table artifact. Make the children
plain routes in your app family:

```dart
final class BillList extends AppRoute { const BillList(); }
final class BillDetail extends AppRoute {
  const BillDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}
```

Call sites that pushed the **parent** push the initial child instead:

```dart
context.push(const BillList());     // was: router.push(BillRouterRoute())
```

Back behaviour is unchanged — `[Home, BillList, BillDetail]` pops exactly as
the nested stack did.

### 2. A section with its own preserved stack → a module

If leaving the section and returning had to restore where you were, that
history is real state, and a [module](/guides/modules/) owns it: a route
family, an initial stack, a page builder, and its own URL prefix, mounted at
a marker route on the host stack.

```dart
final class BillsMount extends AppRoute { const BillsMount(); }

class BillsModule extends RouteModule<BillRoute> {
  const BillsModule();

  @override
  List<BillRoute> get initialStack => const [BillList()];

  @override
  Widget buildPage(BuildContext context, BillRoute route) => switch (route) {
    BillList() => const BillListScreen(),
    BillDetail(:final id) => BillDetailScreen(id: id),
  };
}
```

The host renders the marker with the mount:

```dart
BillsMount() => const KaiselModuleMount<BillRoute>(module: BillsModule()),
```

Pushing the parent route translates directly: `push(const BillsMount())`. The
module's nested navigator, its own back stack, and its `/bills` URL prefix
(via `ModuleStackCodec` + `ConfigCodecWithModules`) all line up with what the
`AutoRouter` parent was doing.

### 3. A tab or bottom-nav section → a shell branch

If the parent was reached through persistent chrome rather than a push, it is
a [shell branch](/guides/shells/): one `KaiselBranchSpec` per section, each
with its own sealed family and live stack. "Pushing the parent" becomes
`context.shell().switchTo(index)`.

### Choosing

| The parent existed to… | Use |
| --- | --- |
| group routes in the config file | flatten — plain routes |
| keep a section's back stack alive across visits | a module |
| back a tab in persistent chrome | a shell branch |
| scope a feature owned by another team | a module (it owns its codec too) |

Flatten first if you are unsure: it is the smallest change, and a module or
branch can be introduced later without touching the screens themselves.

## Already at parity — or better

**DevTools.** kaisel ships its own zero-integration DevTools extension — a live
inspector of the stack, shells, modules, flows, guard trace, and a transitions
log showing the call site behind each navigation. Open DevTools in any debug run.

**Route observation.** auto_route's `AutoRouteAware` mixin makes route observation
declarative; kaisel uses standard Flutter `NavigatorObserver`s via the `observers:`
builder — a `RouteObserver` / `RouteAware` works on the main stack, and since 0.20
even sees a modal flow open and close.

**State restoration.** Like auto_route, kaisel supports Flutter's
`RestorationManager` integration so stacks survive Android's "kill background
process" behavior — opt in with `restorationScopeId` on your `MaterialApp` (added
in 0.22).

## A worked example diff

A small app — Home + ProductList + ProductDetail + Login + auth guard —
typically loses around 30% of its routing-related code on migration,
mostly to deletion of `.gr.dart` files and codegen scaffolding. The
net diff is also one fewer `pubspec.yaml` dependency and one fewer
`dev_dependencies` build step.

The example folder in this repo contains
[`main.dart`](../../example/lib/main.dart),
[`main_shell_adaptive.dart`](../../example/lib/main_shell_adaptive.dart), and
[`main_nested_flows.dart`](../../example/lib/main_nested_flows.dart) — they
demonstrate the same patterns this guide describes. If you're stuck on
how a specific auto_route construct translates, scan those for a
working analogue.

## More questions

File an issue at the [kaisel repo][2] with the auto_route construct
you can't figure out how to translate. Migration-shaped questions are
the highest-value GitHub conversations to have right now because they
inform what this guide should cover next.

[2]: https://github.com/Mastersam07/kaisel
