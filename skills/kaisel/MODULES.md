# Modules

Reference for `RouteModule`, `KaiselModuleMount`, `ModuleStackCodec`,
and `ConfigCodecWithModules`. Use modules when an app's routes split
naturally along feature boundaries — a shop subsystem, an auth
subsystem, a settings subsystem — and you want each to own its routes,
page builders, and codec independently.

## The model

A `RouteModule` is a self-contained unit that owns:

- Its own sealed route hierarchy (`ShopRoute`, `AuthRoute`, etc.).
- Its own page builder over those routes.
- Its own codec for the URLs it handles.

Modules mount under a path prefix in the main app. The main codec
delegates URL parsing to whichever module's prefix matches; the page
builder delegates rendering to whichever module owns the top route.

This is similar to how a backend framework might mount sub-routers
under `/api/v1/users/...` and `/api/v1/orders/...` — kaisel's modules
do the same for client-side routing.

**When NOT to reach for modules:** Single-team apps with one shared
route hierarchy don't need them. Modules pay for themselves when
multiple teams or features want to evolve their routes independently,
or when an app is large enough that one giant sealed type and one
giant page-builder switch are starting to hurt.

## Quick reference

| Type | Purpose |
|:-----|:--------|
| `RouteModule<R>` | Abstract base. A module owns a route family and exposes a page builder + codec. |
| `KaiselModuleMount<R>` | Describes where a module is mounted in the parent app (path prefix + module instance). |
| `ModuleStackCodec<R>` | Codec for a single module's routes. |
| `UntypedModuleStackCodec` | Type-erased module codec, used by the parent app's composite codec. |
| `ConfigCodecWithModules<R>` | Parent codec that delegates URL parsing across mounted modules. |

## Defining a module

```dart
// Module's own route family — sealed, scoped to the module.
sealed class ShopRoute extends KaiselRoute {
  const ShopRoute();
}

final class ShopHome extends ShopRoute {
  const ShopHome();
}

final class ShopProductDetail extends ShopRoute {
  const ShopProductDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

// The module itself.
class ShopModule extends RouteModule<ShopRoute> {
  ShopModule();

  @override
  Widget buildPage(BuildContext context, ShopRoute route) => switch (route) {
    ShopHome() => const ShopHomeScreen(),
    ShopProductDetail(:final id) => ShopProductDetailScreen(id: id),
  };

  @override
  ModuleStackCodec<ShopRoute> get codec => _ShopCodec();
}

class _ShopCodec extends ModuleStackCodec<ShopRoute> {
  @override
  List<ShopRoute>? decode(List<String> segments) {
    return switch (segments) {
      [] => [const ShopHome()],
      ['products', final id] => [const ShopHome(), ShopProductDetail(id)],
      _ => null,  // not ours — let another module try
    };
  }

  @override
  List<String> encode(List<ShopRoute> stack) {
    final top = stack.last;
    return switch (top) {
      ShopHome() => [],
      ShopProductDetail(:final id) => ['products', id],
    };
  }
}
```

A few things to notice:

- The module's codec returns `null` from `decode` when the segments
  don't belong to it. That's the "let another module try" signal.
- `decode` returns a stack, not a single route — same logic as the
  top-level codec, so deep links land with a coherent back history.
- `encode` produces relative segments, *not* the absolute path. The
  parent composite codec prepends the mount prefix.

## Mounting modules in the parent app

```dart
final shopModule = ShopModule();
final authModule = AuthModule();

class AppCodec extends ConfigCodecWithModules<AppRoute> {
  AppCodec() : super(modules: [
    KaiselModuleMount(prefix: 'shop', module: shopModule),
    KaiselModuleMount(prefix: 'auth', module: authModule),
  ]);

  @override
  KaiselConfig<AppRoute> decodeNonModule(Uri uri) {
    // Handle non-module URIs (routes owned directly by the parent).
    return switch (uri.pathSegments) {
      [] || ['home'] => KaiselConfig(mainStack: [const Home()]),
      _ => KaiselConfig(mainStack: [NotFound(uri)]),
    };
  }

  @override
  Uri encodeNonModule(KaiselConfig<AppRoute> config) {
    // Encode non-module routes back to URIs.
    final top = config.mainStack.last;
    return switch (top) {
      Home() => Uri(path: '/home'),
      NotFound(:final uri) => uri,
      _ => Uri(path: '/'),
    };
  }
}
```

The parent codec tries each mounted module in order. Whichever
module's prefix matches the URI's first segment gets the rest of the
segments passed to its codec. Order matters — first-matching wins.

## Module page builder integration

The parent app's page builder delegates to the module when the top
route belongs to it:

```dart
KaiselRouterDelegate<AppRoute>(
  router: _router,
  builder: (context, route) {
    // Modules own their route types — delegate when the route is
    // theirs.
    if (route is ShopRoute) return shopModule.buildPage(context, route);
    if (route is AuthRoute) return authModule.buildPage(context, route);

    // Parent-owned routes fall through.
    return switch (route as AppRoute) {
      Home() => const HomeScreen(),
      NotFound(:final uri) => NotFoundScreen(uri: uri),
      _ => const SizedBox.shrink(),
    };
  },
);
```

Note that this requires `AppRoute` to be a union that includes the
module's route types — typically by having the module routes implement
or extend `AppRoute`, or by making `AppRoute` itself non-sealed and
relying on the modules' own seal at their level.

## Module ownership of a shell branch

A common pattern: a shell with three tabs, where one tab is owned by
a module. The branch's router is typed to the module's route family;
the branch's page builder is the module's `buildPage`:

```dart
KaiselBranch<ShopRoute>(
  router: _shopRouter,
  pageBuilder: shopModule.buildPage,
)
```

The module's page builder is the right signature for the branch.
No glue code needed.

## Module-owned codec for a shell branch

When the shell's URL needs to address the active branch's stack and
the branch is owned by a module:

```dart
class AppCodec extends KaiselConfigCodec<AppRoute> {
  AppCodec({required this.shopModule});
  final ShopModule shopModule;

  @override
  KaiselConfig<AppRoute> decode(Uri uri) {
    return switch (uri.pathSegments) {
      ['shop', ...final rest] => KaiselConfig(
        mainStack: [const ShellHost()],
        shell: KaiselShellConfig(
          activeBranch: 1,  // shop branch
          branchStacks: [
            [const HomeView()],
            shopModule.codec.decode(rest) ?? [const ShopHome()],
            [const SettingsHome()],
          ],
        ),
      ),
      // ... other URL forms
    };
  }
}
```

The shop module's codec parses the part of the URL it owns
(`['products', '42']` after stripping the `shop` prefix); the parent
codec stitches the result into the shell config.

## Should you use modules?

Modules are infrastructure for separation, not a default. Reach for
them when:

- Multiple feature teams own different parts of the app and need to
  evolve routes without coordinating.
- The app has 50+ screens and the central sealed type is becoming
  unwieldy.
- A shared kaisel-based core needs to host plugins or feature
  modules from external packages.

Don't reach for them when:

- The app is single-team and under 30 screens. The overhead exceeds
  the win.
- You want modules just to "organise" routes within one team's
  codebase. Use directory structure and sub-files within one sealed
  hierarchy instead.
- You're migrating from go_router or auto_route and trying to map
  their structure 1:1. Start with one sealed hierarchy; introduce
  modules later if the size justifies it.

## Common mistakes

| Mistake | Fix |
|:--------|:----|
| Module codecs returning absolute paths in `encode` | Return relative segments — the parent prepends the mount prefix. Returning `'/shop/products/42'` from the shop module breaks the composition. |
| Module codecs that don't return `null` for non-owned URIs | If `decode` always returns a stack (even an empty one), the parent composite codec can't tell which module owns a URI. Always `return null` for unrecognised segments. |
| Mounting modules whose route types don't compose into a parent union | The parent's `AppRoute` needs to be a union that includes module route types. Either extend `AppRoute` in module routes, or design `AppRoute` to be open enough to admit them. |
| Module instances stored as singletons that outlive the router | Modules don't own router state, but if their codec or page builder closes over service references that get disposed, the module breaks. Construct modules in the same lifecycle as the router. |
| Using modules to share code between unrelated apps | Modules are a separation pattern within one app. Share a `RouteModule` between two apps and you've coupled them. Use a shared package for the routes; let each app construct its own module. |
