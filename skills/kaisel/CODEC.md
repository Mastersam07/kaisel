# Codec — URLs and deep linking

Reference for `KaiselConfigCodec<R>`, `KaiselStackCodec<R>`,
`StackToConfigCodec`, and `KaiselRouteInformationParser`. The codec is
the single place URL strings live in a kaisel app. Everywhere else
reasons about typed routes; the codec is the bridge.

## The model

The article's pitch about codec-as-bridge is load-bearing here.
Sealed routes are the source of truth — they hold the data, drive the
page builder, define equality. URLs are a *serialization layer*
produced by a codec when the platform asks for one (web URL bar,
Android deep link intent, browser back history, app launch URL).

Two roles the codec plays:

1. **Decode** — `Uri → KaiselConfig<R>`. When a URL arrives (initial
   launch, deep link, browser navigation), the codec parses it into a
   typed stack. The router then `set`s that stack.
2. **Encode** — `KaiselConfig<R> → Uri`. When the stack changes, the
   codec produces the URL that represents it. The platform's URL bar
   (or browser history, or saved-state mechanism) updates accordingly.

Both directions are written exhaustively over the sealed type. The
compiler will tell you when a new route variant needs a URL form.

## Quick reference

| Type | Purpose |
|:-----|:--------|
| `KaiselConfig<R>` | The serializable shape of the router's state. Wraps the `mainStack`, plus nested configs for shells/modules. |
| `KaiselConfigCodec<R>` | Abstract codec. Subclass it and implement `decode` / `encode`. Use this when the app has shells, modules, or nested routers (URLs need to address branch state, not just the main stack). |
| `KaiselStackCodec<R>` | Older, simpler codec — handles only the main stack as a `List<R>`. Adequate for apps without shells. |
| `StackToConfigCodec<R>` | Adapter wrapping a `KaiselStackCodec<R>` so it works where a `KaiselConfigCodec<R>` is expected. |
| `KaiselRouteInformationParser<R>` | `RouteInformationParser` implementation that delegates to your codec. |

## A real codec

For an app with `Home`, `ProductList`, and `ProductDetail`:

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

      // 404 fallback — render a NotFound route with the offending URI.
      _ => KaiselConfig(mainStack: [NotFound(uri)]),
    };
  }

  @override
  Uri encode(KaiselConfig<AppRoute> config) {
    final top = config.mainStack.last;
    return switch (top) {
      Home() => Uri(path: '/home'),
      ProductList() => Uri(path: '/products'),
      ProductDetail(:final id) => Uri(path: '/products/$id'),
      NotFound(:final uri) => uri,
    };
  }
}
```

Wire it up via the route information parser:

```dart
class _Parser extends KaiselRouteInformationParser<AppRoute> {
  _Parser(this.router) : super(codec: AppCodec());
  @override final KaiselRouter<AppRoute> router;
}

MaterialApp.router(
  routerDelegate: _delegate,
  routeInformationParser: _Parser(_router),
);
```

## Building the stack on deep-link land

A deep link to `/products/sku-42` should land the user at the detail
page *with a coherent back history*. That means the decoded stack
should be three deep: `[Home, ProductList, ProductDetail('sku-42')]`,
not just `[ProductDetail('sku-42')]`. Pressing back returns to the
product list; pressing back again returns home.

This is why `decode` returns a stack, not a single route — the codec
gets to choose the back history. Same URL, well-designed history:

```dart
['products', final id] => KaiselConfig(
  mainStack: [const Home(), const ProductList(), ProductDetail(id)],
),
```

Same URL, bad history (no breadcrumb back):

```dart
['products', final id] => KaiselConfig(
  mainStack: [ProductDetail(id)],
),
```

Pick the back history that makes sense in the app's information
architecture, not the shallowest one that matches the URL.

## Routes that don't have URL forms

Some routes carry non-serializable data (a `Product` model object
rather than just an id, a callback function passed at push time, a
file handle). These can't roundtrip through URLs. Express them as
sealed variants of the same destination:

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
in-app push only, and the page builder pattern-matches on which one
arrived. If a `ProductDetailWithModel` is on top when `encode` runs,
fall back to the id-based form (best-effort URL) or to an opaque URL
that the platform can use for browser history without round-tripping:

```dart
Uri encode(KaiselConfig<AppRoute> config) {
  final top = config.mainStack.last;
  return switch (top) {
    ProductDetailById(:final id) => Uri(path: '/products/$id'),
    ProductDetailWithModel(:final product) =>
      Uri(path: '/products/${product.id}'),  // best-effort
    // ...
  };
}
```

This pattern replaces go_router's `extra` field with something
type-checked: the route variants encode what's known statically, and
each branch handles its data without dynamic casting.

## Shells and codecs

When the app uses `KaiselBranchedShell`, the URL needs to address
both the active branch and the active branch's sub-stack. The
`KaiselConfig<R>` type carries this via `KaiselShellConfig`:

```dart
@override
KaiselConfig<AppRoute> decode(Uri uri) {
  return switch (uri.pathSegments) {
    ['home', ...] => KaiselConfig(
      mainStack: [const ShellHost()],
      shell: KaiselShellConfig(
        activeBranch: 0,
        branchStacks: [
          [const HomeView()],  // home branch
          [const ProductList()],  // product branch (initial)
          [const SettingsHome()],  // settings branch (initial)
        ],
      ),
    ),
    ['products'] => KaiselConfig(
      mainStack: [const ShellHost()],
      shell: KaiselShellConfig(
        activeBranch: 1,
        branchStacks: [
          [const HomeView()],
          [const ProductList()],
          [const SettingsHome()],
        ],
      ),
    ),
    ['products', final id] => KaiselConfig(
      mainStack: [const ShellHost()],
      shell: KaiselShellConfig(
        activeBranch: 1,
        branchStacks: [
          [const HomeView()],
          [const ProductList(), ProductDetail(id)],
          [const SettingsHome()],
        ],
      ),
    ),
    // ...
  };
}
```

The shell config carries per-branch stacks. On deep-link land, every
branch gets initialised to a sensible stack — only the active branch
typically has a deep history; the others sit at their initial state
(`[ProductList()]`, etc.).

## Browser back and history

When the codec is configured, the platform's URL bar and browser
history work without further code: every stack mutation triggers an
encode pass, and the result is reported to Flutter's
`RouteInformationProvider`, which the browser uses as the URL.

On the web specifically, kaisel's integration is less polished than
go_router's native one. Test browser back, forward, and direct URL
entry on a migration branch if web is the primary target — the codec
handles the model layer, but URL strategy (hash vs. path), 404
behaviour, and refresh handling all need to be exercised.

## Common mistakes

| Mistake | Fix |
|:--------|:----|
| Decoding to a single-route stack like `[ProductDetail(id)]` when the URL has obvious parent breadcrumbs | Decode to the full breadcrumb stack `[Home, ProductList, ProductDetail(id)]`. Back navigation needs a coherent history. |
| Falling through `decode` without a 404 case | Use a `NotFound(uri)` route and a `_ => KaiselConfig(mainStack: [NotFound(uri)])` arm. Better than silently throwing or returning empty. |
| Trying to encode a non-URL-routable variant exhaustively | Split the destination into sealed variants — one URL-routable, one in-app only. The encode method handles each explicitly. |
| Not testing browser back / forward / refresh on the web | The codec doesn't guarantee browser-bar behaviour by itself; the platform integration has rough edges. Test it. |
| Putting query parameters in the route as a string blob | Parse them into typed fields in `decode` and reconstruct in `encode`. The route should hold typed values, not raw URI fragments. |
| Decoding URLs case-sensitively when the path is conceptually case-insensitive | Lowercase `uri.pathSegments` before matching, or use case-insensitive matching. `/Products/sku-42` should resolve to the same route as `/products/sku-42` for most apps. |
