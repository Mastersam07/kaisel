# Migrating from go_router to kaisel

If you're reading this, you've already decided — or mostly decided —
that you want to move. This guide is the practical work: what
translates, what doesn't, and what the diff against your existing
codebase will look like. It isn't a sales pitch for kaisel (that's
the [Routes as Values][1] article) and it isn't a list of grievances
against go_router. Pragmatic translation, honest about effort.

[1]: https://medium.com/@codefarmer/flutter-routes-as-values-089476ad4d5b

## The short version

go_router thinks in string paths matched against a route table.
kaisel thinks in sealed values that are the source of truth, with
URLs derived from them by a codec when you need URLs at all. The
gap between these mental models is wider than the gap from auto_route
to kaisel, and the migration is correspondingly more philosophical
in places.

The mechanical translation is straightforward for simple apps. The
work concentrates in three areas: the global `redirect:` callback
(becomes a guard pipeline), `ShellRoute` / `StatefulShellRoute`
(becomes `KaiselBranchedShell`, with state preservation as the
default rather than as the stateful variant), and the URL story
(string patterns disappear; a codec replaces them).

For an app of about thirty screens with one shell and a redirect-based
auth flow, plan three to four days. Most of that is mechanical;
the slow part is testing that deep-link parity still holds.

## Before you start

A few questions worth answering honestly before you begin.

**Are you using `StatefulShellRoute` or the older non-stateful `ShellRoute`?**
If non-stateful, your app probably treats tab switches as losing
intra-tab navigation state. kaisel's branched shell preserves
per-tab state by default — your tabs will behave differently after
migration. Decide whether that's the new desired behavior, or
whether you need to actively reset stacks on tab switches to
preserve current UX.

**Does your app rely on go_router's `extra` field for non-serializable
payloads?** kaisel doesn't have an equivalent — instead, you put
the data on the route directly. That's cleaner, but it means routes
that carry rich payloads can't be roundtripped through URLs (which
is honest — they couldn't be roundtripped through go_router's
`extra` field either, despite the API suggesting they could).

**Do you rely on browser history / deep linking in production?**
If yes, the codec is a load-bearing piece of the migration and worth
writing carefully. If no, you can use a no-op parser and skip the
codec entirely.

## Concept mapping

| go_router                                       | kaisel                                              |
| ----------------------------------------------- | --------------------------------------------------- |
| `GoRoute(path: '/products/:id', builder: ...)`  | `final class ProductDetail extends AppRoute` + a switch arm |
| Path params `:id` parsed to `state.params['id']`| Constructor field `final String id`                 |
| Query params `state.uri.queryParameters`        | Constructor fields on the route                     |
| `extra: nonSerializableObject`                  | Another field on the route                          |
| Global `redirect: (ctx, state) => ...`          | Guard function `(current, proposed) → stack` in the pipeline |
| Per-route `redirect:`                           | Same pipeline; pattern-match on the route           |
| `ShellRoute`                                    | A single-branch `KaiselBranchedShell` or custom     |
| `StatefulShellRoute.indexedStack`               | `KaiselBranchedShell` with N branches               |
| `context.go('/products/42')`                    | `context.router<AppRoute>().set([const Home(), ProductDetail('42')])` |
| `context.push('/products/42')`                  | `context.router<AppRoute>().push(const ProductDetail('42'))` |
| `context.pop()`                                 | `context.router<AppRoute>().pop()`                  |
| `context.replace('/login')`                     | `context.router<AppRoute>().replaceTop(const Login())` |
| `go_router_builder` (optional codegen)          | Sealed types; no build step                         |
| `errorBuilder:`                                 | An error route variant in your sealed type          |

A row-by-row read can hide the conceptual shift: the left column
treats URLs as the primary representation; the right column treats
sealed values as primary. Everything else cascades from that
distinction.

## The migration in six steps

### 1. Project setup

Swap go_router for kaisel in `pubspec.yaml`:

```diff
 dependencies:
   flutter:
     sdk: flutter
-  go_router: ^14.0.0
+  kaisel: ^0.13.0
```

If you used `go_router_builder` for typed routes, drop both that and
`build_runner` (if it isn't being used by something else). Delete
any generated `*.g.dart` files associated with routing.

### 2. Translate GoRoute definitions to sealed routes

Each `GoRoute` in your route table becomes a sealed class variant.
The screen widget stays mostly the same — the difference is that
its constructor takes its parameters directly instead of plucking
them out of `GoRouterState`.

**Before** (go_router):

```dart
GoRoute(
  path: '/products/:id',
  builder: (context, state) {
    final id = state.pathParameters['id']!;
    return ProductDetailScreen(id: id);
  },
),
```

**After** (kaisel):

```dart
// 1. Define the route in your sealed hierarchy.
final class ProductDetail extends AppRoute {
  const ProductDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

// 2. Handle it in the page builder.
KaiselRouterDelegate<AppRoute>(
  router: router,
  builder: (context, route) => switch (route) {
    Home() => const HomeScreen(),
    ProductDetail(:final id) => ProductDetailScreen(id: id),
    // ... other routes
  },
);
```

The compiler now enforces that you've handled every variant —
the `switch` errors if you add a new sealed subclass and forget
to update the builder. Path-shaped strings disappear from this
layer entirely. They reappear (if you need them) in the codec.

Group your routes into a single sealed hierarchy:

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

### 3. Replace path/query parameters with constructor fields

Anywhere you read `state.pathParameters['something']` or
`state.uri.queryParameters['filter']`, the value becomes a field on
the route class. Optional params become nullable fields with
defaults; required params become required positional or named args.

**Before** (go_router):

```dart
GoRoute(
  path: '/products',
  builder: (context, state) {
    final category = state.uri.queryParameters['category'];
    final sortBy = state.uri.queryParameters['sort'] ?? 'name';
    return ProductListScreen(category: category, sortBy: sortBy);
  },
),
```

**After** (kaisel):

```dart
final class ProductList extends AppRoute {
  const ProductList({this.category, this.sortBy = 'name'});
  final String? category;
  final String sortBy;
  @override
  List<Object?> get props => [category, sortBy];
}
```

URL parsing moves into the codec (step 6). The route itself just
holds the data.

### 4. Replace `redirect:` with a guard pipeline

go_router's `redirect:` callback returns a path string (or `null`).
kaisel's guards return a stack. The conceptual difference is that
a guard can express things a redirect can't — it sees the entire
proposed stack, not just the destination.

**Before** (go_router):

```dart
GoRouter(
  redirect: (context, state) {
    final loggingIn = state.matchedLocation == '/login';
    if (!isLoggedIn && !loggingIn) {
      return '/login';
    }
    return null;
  },
  routes: [...],
);
```

**After** (kaisel):

```dart
List<AppRoute> authGuard(List<AppRoute> current, List<AppRoute> proposed) {
  final headingToLogin = proposed.any((r) => r is Login);
  if (!isLoggedIn && !headingToLogin) {
    return [const Login()];
  }
  return proposed;
}

final router = KaiselRouter<AppRoute>(
  initial: isLoggedIn ? const Home() : const Login(),
  guards: [authGuard],
);
```

Multiple cross-cutting concerns compose as a list of guards, each
receiving the output of the previous:

```dart
KaiselRouter<AppRoute>(
  initial: const Home(),
  guards: [authGuard, featureFlagGuard, entitlementGuard],
)
```

This is closer to a function pipeline than to "callbacks attached
to routes" — and that's the point. Per-route guards in go_router's
model (which it doesn't directly support, only at the top level)
are awkward because the route is the wrong place to express
cross-cutting concerns. The pipeline expresses them once, applies
them everywhere.

### 5. Translate `ShellRoute` / `StatefulShellRoute`

If you're on `StatefulShellRoute.indexedStack`, this maps cleanly to
`KaiselBranchedShell`. If you're on the non-stateful `ShellRoute`,
the migration changes the runtime behavior (per-tab state is now
preserved), so plan accordingly.

**Before** (go_router):

```dart
StatefulShellRoute.indexedStack(
  builder: (context, state, navigationShell) => ScaffoldWithNavBar(
    navigationShell: navigationShell,
  ),
  branches: [
    StatefulShellBranch(routes: [
      GoRoute(path: '/home', builder: ...),
    ]),
    StatefulShellBranch(routes: [
      GoRoute(path: '/products', builder: ...),
      GoRoute(path: '/products/:id', builder: ...),
    ]),
  ],
);
```

**After** (kaisel):

```dart
// Per-branch sealed routes.
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

// Shell host widget.
class _AppShellState extends State<AppShell> {
  late final _homeRouter = KaiselRouter<HomeRoute>(initial: const HomeView());
  late final _productRouter = KaiselRouter<ProductRoute>(initial: const ProductList());
  late final _shell = BranchedShellRouter(branches: [_homeRouter, _productRouter]);

  @override
  Widget build(BuildContext context) {
    return KaiselBranchedShell(
      shell: _shell,
      branches: [
        KaiselBranch<HomeRoute>(
          router: _homeRouter,
          pageBuilder: (c, r) => switch (r) {
            HomeView() => const HomeScreen(),
          },
        ),
        KaiselBranch<ProductRoute>(
          router: _productRouter,
          pageBuilder: (c, r) => switch (r) {
            ProductList() => const ProductListScreen(),
            ProductDetail(:final id) => ProductDetailScreen(id: id),
          },
        ),
      ],
      chromeBuilder: (context, activeBranch, branchContent, switchBranch) {
        return Scaffold(
          body: branchContent,
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: activeBranch,
            onTap: switchBranch,
            items: const [/* ... */],
          ),
        );
      },
    );
  }
}
```

Per-branch typing is doing real work here. Each tab's `KaiselRouter`
is typed to that tab's sealed family. The compiler will reject
`_homeRouter.push(const ProductDetail('x'))` as a type error —
you can't accidentally push a product route into the home tab's
stack. This is the type safety go_router's table can't give you
even with codegen.

### 6. Wire up the codec

This is the step that doesn't exist in the auto_route guide because
auto_route already has typed routes and a codegen-driven parser.
go_router migration almost always needs this step because you
likely have deep links to maintain.

If you don't use deep links at all, use a no-op parser:

```dart
class _NoopParser extends RouteInformationParser<KaiselConfig<AppRoute>> {
  _NoopParser(this.router);
  final KaiselRouter<AppRoute> router;
  @override
  Future<KaiselConfig<AppRoute>> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    return KaiselConfig<AppRoute>(mainStack: router.stack);
  }
}
```

If you do, write a real codec. The codec maps `Uri ↔ KaiselConfig`,
and you register it with the parser:

```dart
class AppCodec extends KaiselConfigCodec<AppRoute> {
  @override
  KaiselConfig<AppRoute> decode(Uri uri) {
    return switch (uri.pathSegments) {
      [] || ['home'] => KaiselConfig(mainStack: [const Home()]),
      ['products'] => KaiselConfig(
        mainStack: [const Home(), const ProductList()],
      ),
      ['products', final id] => KaiselConfig(
        mainStack: [const Home(), const ProductList(), ProductDetail(id)],
      ),
      _ => KaiselConfig(mainStack: [const Home()]),  // 404 fallback
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

The pattern matching in `decode` is exhaustive on the level you
specify (path segments), and the encoder is exhaustive on your
sealed type — if you add a new route variant and forget to give it
a URL, the compiler tells you.

A note on what to do about routes that *don't* have URL forms. If
`ProductDetail` is reachable in two ways — by id (URL-routable) and
by full model (in-app push only) — you express that as sealed
variants of the same destination:

```dart
sealed class ProductDetail extends AppRoute {
  const ProductDetail();
}
final class ProductDetailById extends ProductDetail {
  const ProductDetailById(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}
final class ProductDetailWithModel extends ProductDetail {
  const ProductDetailWithModel(this.product);
  final Product product;
}
```

The codec only handles `ProductDetailById`. The other variant is
in-app only, and the screen pattern-matches on which it received.
This replaces go_router's `extra` field with something type-checked.

## What kaisel doesn't yet do at parity

Be honest with yourself about whether these matter before migrating.

**State restoration.** go_router supports the Flutter
`RestorationManager` integration that lets stacks survive Android
process death. kaisel doesn't, yet — it's on the roadmap.
If your app relies on this in production, wait.

**Browser back-button history on the web.** go_router integrates
with `RouteInformationProvider` and handles browser history natively.
kaisel does the same in principle (via the codec round-tripping),
but the integration is less polished than go_router's. If your app
is web-first, test this carefully on a migration branch before
committing.

**DevTools extension.** go_router has community extensions and
observable router output. kaisel's devtools extension is on the
roadmap. Until then, debugging is `print` statements or your own
listener attached to the router.

**`errorBuilder:`.** go_router has a built-in error page when no
route matches. kaisel doesn't have a separate slot; you add an
error route to your sealed type and fall through to it in the codec:

```dart
final class NotFound extends AppRoute {
  const NotFound(this.uri);
  final Uri uri;
  @override
  List<Object?> get props => [uri];
}

// In codec.decode:
_ => KaiselConfig(mainStack: [NotFound(uri)]),
```

It's slightly more code but it makes errors first-class routes,
which means you can navigate to them, log them, instrument them.

**Initial location from a saved state.** go_router's
`initialLocation` parameter has straightforward semantics. kaisel's
`initial` takes a route, not a URL — to launch from a saved URL,
you decode it through the codec yourself before constructing the
router.

## Migration strategy: big bang, not incremental

You can technically run both routers side by side in the same app
(two `MaterialApp.router`s in a tree), but you almost never want
to. The complexity isn't worth it for any app smaller than a
hundred screens. The recommendation is: pick a week, branch from
main, do the rewrite, regression-test, ship.

The reason big-bang is the right answer is that route-related code
in your app is more interconnected than you remember. Every screen
that uses `context.go(...)` is coupled to your route table. Every
guard touches the redirect callback. Every deep link touches the
parser. Switching the router under any of these means switching
them all. There's no clean line to draw across the codebase that
lets half stay on go_router and half move to kaisel.

If you can't afford a one-week branch, you can't afford the
migration yet — wait for a quieter sprint.

## A worked example diff

A small app — Home + ProductList + ProductDetail + Login + a
StatefulShellRoute with two tabs + auth redirect — typically loses
about 20% of its routing-related code on migration. The string
paths disappear, the redirect callback compresses into a single
guard function, and the route table becomes a switch expression.
The largest single addition is the codec, which is new code that
didn't exist in the go_router version.

The example folder in this repo contains
[`main.dart`](../../example/lib/main.dart),
[`main_shell_adaptive.dart`](../../example/lib/main_shell_adaptive.dart),
and [`main_media_cataloguer.dart`](../../example/lib/main_media_cataloguer.dart) —
they demonstrate the same patterns this guide describes. If you're
stuck on how a specific go_router construct translates, scan those
for a working analogue.

## More questions

File an issue at the [kaisel repo][2] with the go_router construct
you can't figure out how to translate. Migration-shaped questions
are the highest-value GitHub conversations to have right now —
they inform what this guide should cover next, and they help shape
the parser API as it firms up toward v1.0.

[2]: https://github.com/Mastersam07/kaisel
