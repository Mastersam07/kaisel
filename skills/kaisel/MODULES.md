# Modules

Your app's routes split along feature or team boundaries — a shop, an
auth flow, an admin area — and each should own its routes without the
app knowing their internals.

Reference for `RouteModule`, `KaiselModuleMount`, `ModuleStackCodec`,
and `ConfigCodecWithModules`. Modules are kaisel's other form of
**nested routing** — a feature's routes as a self-contained, mountable
stack on its own nested Navigator. Use modules when an app's routes split
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
| `RouteModule<R>` | Abstract base. A module owns a route family and exposes `initialStack`, `buildPage`, and an optional `codec`. |
| `KaiselModuleMount<R>` | The **widget** that mounts a `RouteModule` at a host marker route; creates the module's own typed sub-router internally. |
| `ModuleMount<HostR>` | A URL-composition **declaration**: host marker route + URL prefix + the module's codec. Goes in `ConfigCodecWithModules.modules`. |
| `ModuleStackCodec<R>` | Codec for a single module's routes (`encode`/`decode` over `List<String>` segments, relative to the mount prefix). |
| `UntypedModuleStackCodec` | Type-erased module codec, used by the composer to hold modules of differing route types. |
| `ConfigCodecWithModules<R>` | Concrete host codec — **construct** it with a `baseCodec` and a list of `ModuleMount`s; don't subclass it. |

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
  const ShopModule();

  @override
  List<ShopRoute> get initialStack => const [ShopHome()];

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

## Mounting a module in the parent app

A module mounts at a **marker route** on the host's sealed type. The
host's page builder renders that marker with a `KaiselModuleMount<R>`
widget, which creates the module's own typed sub-router internally —
the host doesn't dispatch the module's routes itself.

```dart
// Marker route on the host's AppRoute.
final class ShopMount extends AppRoute { const ShopMount(); }

Widget _buildMainPage(BuildContext context, AppRoute route) =>
    switch (route) {
      Home() => const HomeScreen(),
      ShopMount() => const KaiselModuleMount<ShopRoute>(module: ShopModule()),
      // ... other host-owned routes
    };
```

Inside the module's screens, `context.router<ShopRoute>()` resolves to
the module's sub-router — pushing a `ShopRoute` typechecks; pushing an
`AppRoute` is a compile error. `context.router<AppRoute>().pop()` pops
the `ShopMount` off the host stack, which is how the module exits itself.

URL composition is done by **constructing** a `ConfigCodecWithModules`
(it's a concrete codec, not a base class to extend) from the host's base
codec plus one `ModuleMount` per module:

```dart
final appCodec = ConfigCodecWithModules<AppRoute>(
  baseCodec: _MainAppCodec(),        // a KaiselConfigCodec for host routes
  modules: [
    ModuleMount(
      mountRoute: const ShopMount(), // host marker route
      prefix: '/shop',               // URL prefix the module owns
      codec: _ShopCodec(),           // the module's ModuleStackCodec
    ),
  ],
);
```

A URL under `/shop/...` is handed to the module's codec (relative to the
prefix); everything else goes to `baseCodec`. The base codec stays
module-agnostic — adding a module means appending a `ModuleMount`, not
editing the base codec. Modules are tried in order; list a longer prefix
(`/shop/v2`) before a shorter one (`/shop`) if they overlap.

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
  const AppCodec();

  static const _shopCodec = _ShopCodec();

  @override
  KaiselConfig<AppRoute>? decode(Uri uri) {
    return switch (uri.pathSegments) {
      ['shop', ...final rest] => KaiselConfig(
        mainStack: [const ShellHost()],
        // nestedState holds ONLY the active branch's stack. The shop
        // module's codec decodes the segments after the prefix.
        nestedState: KaiselShellConfig(
          activeBranch: 1, // shop branch
          activeBranchStack: _shopCodec.decode(rest) ?? const [ShopHome()],
        ),
      ),
      _ => null,
    };
  }

  @override
  Uri encode(KaiselConfig<AppRoute> config) => /* ... */;
}
```

`KaiselShellConfig` carries the active branch index and that one
branch's stack (`activeBranchStack`), not a stack-per-branch — inactive
branches keep their in-memory state off the URL. The module's codec
parses the segments it owns (`['products', '42']` after the `/shop`
prefix is stripped); the host stitches the result into the branch stack.

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
