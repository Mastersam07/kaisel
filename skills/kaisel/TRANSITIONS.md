# Transitions

You want screens to animate the way the design says — a fade between
auth states, a sheet sliding up, a cross-fade between siblings —
instead of the default platform slide.

Reference for `KaiselPageWrapper`, `KaiselPageWrapperContext`, and the
custom `Page<T>` subclasses you'll write to drive specific animations.
Use this when default `MaterialPage` slide-on-push isn't what the
design calls for — fade between auth states, slide-up modally for
sheets, cross-fade between sibling details, etc.

## The model

By default, `KaiselRouterDelegate` wraps every route in a `MaterialPage`
off the web (the native transition — on recent Flutter, Android's default is
already predictive-back-aware; `androidPredictiveBack` on the config/delegate
guarantees it on older Flutter and under theme overrides), and a quick
**fade** on the web — where `MaterialPage`'s OS-derived slide feels out of
place. Set `webTransition:`
on the config/delegate to change the web default: `KaiselWebTransition.fade`
(default), `.none`, or `.platform` to keep the OS transition. To customise
fully, pass a `pageWrapper` to the delegate. The wrapper receives a
`KaiselPageWrapperContext<R>` describing what's being added or
replaced, and returns a `Page<Object?>` subclass that determines the
transition.

**Predictive back has three gates**, and all must be open to see it: the OS
delivers the gesture on Android 14+ to apps opted in with
`android:enableOnBackInvokedCallback="true"` on the manifest's
`<application>` — the default once an app targets SDK 36 on Android 16.
(Android 13 accepts the flag but lacks the gesture-progress APIs, and
Android 12 and below never engage it.) Flutter's default Android transition
participates from Flutter 3.44; and `androidPredictiveBack` guarantees
participation on older Flutter or under theme overrides. A custom
`pageWrapper` controls its own transitions either way.

Three things to internalise:

1. **The wrapper picks the *style*, not the *direction*.** Flutter's
   Navigator drives direction (forward on add, reverse on remove); the
   wrapper picks which `Page` subclass — and which `PageRouteBuilder`
   inside it — to construct.
2. **Pattern-match on `(previous, route)` for route-pair logic.** Some
   transitions depend on what was below ("only fade when going from
   `LoginRoute` to `ShellHost`"). The context's `previous` field is
   the entry directly below the new one; pattern-match the pair.
3. **Fall back to `MaterialPage` for the default.** A wrapper that
   doesn't recognise a route pair should return `MaterialPage(key:
   ctx.key, child: ctx.child)` — that's the default slide behaviour,
   not a no-op.
4. **Always pass the route name and arguments to the `Page`.** The
   default wrapper sets `name: ctx.route.routeName` and `arguments:
   ctx.route` on every page. The moment you supply your own
   `pageWrapper`, that is on you — forward both on every `Page` you
   return (custom subclass *and* the `MaterialPage` fallback).
   Omitting them strips the route's identity, so `RouteObserver`s,
   analytics screen tracking, and `RouteAware` widgets stop seeing the
   page.

## Quick reference

| Type | Purpose |
|:-----|:--------|
| `KaiselPageWrapper<R>` | `Page<Object?> Function(KaiselPageWrapperContext<R>)`. Passed to the delegate's `pageWrapper`. |
| `KaiselPageWrapperContext<R>` | `route`, `child`, `key`, `position`, `stackLength`, `previous`, `isFlow`, plus `isTop`/`isBottom` getters. `isFlow` is `true` for a modal-flow page — branch on it to give a flow its own entrance transition. |
| `Page<T>` | Flutter's `Page` API — you subclass this for each transition style. |
| `PageRouteBuilder<T>` | Flutter's low-level route builder for custom transitions. Constructed inside your `Page` subclass's `createRoute`. |

## The canonical pattern

### 1. A custom `Page` for the transition style

```dart
class _FadePage<T> extends Page<T> {
  const _FadePage({
    required LocalKey super.key,
    required this.child,
    super.name,
    super.arguments,
  });
  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) {
    return PageRouteBuilder<T>(
      settings: this,
      pageBuilder: (_, __, ___) => child,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    );
  }
}

class _SlideUpPage<T> extends Page<T> {
  const _SlideUpPage({
    required LocalKey super.key,
    required this.child,
    super.name,
    super.arguments,
  });
  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) {
    return PageRouteBuilder<T>(
      settings: this,
      pageBuilder: (_, __, ___) => child,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      transitionsBuilder: (_, anim, __, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
    );
  }
}
```

### 2. The wrapper function

```dart
Page<Object?> _appPageWrapper(KaiselPageWrapperContext<AppRoute> ctx) {
  // Forward the route's name and arguments on every page so observers,
  // analytics, and RouteAware widgets keep seeing the route identity.
  final name = ctx.route.routeName;
  final arguments = ctx.route;

  return switch ((ctx.previous, ctx.route)) {
    // Login ↔ Shell are full-surface auth states swapped with
    // router.set(...), which collapses the stack to a single entry — so
    // ctx.previous is null here. Match on the destination route type
    // (not the pair) so the swap still cross-fades.
    (_, LoginRoute()) || (_, ShellHost()) =>
      _FadePage<Object?>(
        key: ctx.key,
        name: name,
        arguments: arguments,
        child: ctx.child,
      ),

    // Settings slides up from the bottom whenever it's opened.
    (_, Settings()) =>
      _SlideUpPage<Object?>(
        key: ctx.key,
        name: name,
        arguments: arguments,
        child: ctx.child,
      ),

    // Default: MaterialPage slide.
    _ => MaterialPage<Object?>(
      key: ctx.key,
      name: name,
      arguments: arguments,
      child: ctx.child,
    ),
  };
}
```

### 3. Pass it to the config

`pageWrapper:` is a `KaiselRouterConfig` parameter — declare the config
once at app lifetime and hand it to `MaterialApp.router`:

```dart
final _config = KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  builder: /* ... */,
  pageWrapper: _appPageWrapper,
);

// build: MaterialApp.router(routerConfig: _config, theme: ...)
```

(The lower-tier explicit form still works — pass `pageWrapper:` to
`KaiselRouterDelegate(router:, builder:, pageWrapper:)` if you're
managing the delegate by hand.)

## Pattern shapes you'll write

### Destination-only

"Whenever this route appears on top, use this transition." Match on
the route only:

```dart
(_, Settings()) => _SlideUpPage(/* ... */),
(_, About()) => _FadePage(/* ... */),
```

### Route-pair

"Only style the transition when going from A to B." Match the tuple.
This works when **both** routes are on the rendered stack — i.e. a
push/pop, not a full-stack `set`:

```dart
// Pushing ProductDetail on top of ProductList: previous is ProductList.
(ProductList(), ProductDetail()) => _ZoomPage(/* ... */),
```

`ctx.previous` is the entry directly below the new one on the *rendered*
stack. Flutter's Navigator handles forward vs. reverse direction
automatically — you just declare *that* this pair uses the style. If a
mutation replaces the whole stack with one entry (`router.set([X])`),
`previous` is `null` and a pair match won't fire; match on the route
type alone there (see the auth example above).

### Same-type-on-top (e.g., Product → Product)

"Cross-fade when the new top has the same type as the old top." Useful
for adaptive master-detail or "related items" links where pushing
Detail(b) on top of Detail(a) shouldn't slide:

```dart
(Product(), Product()) => _CrossFadePage(/* ... */),
```

## Direction-aware transitions

The default `Navigator` reverses transitions on pop (push slides left
→ pop slides right). Your custom `Page` inherits this for free if it
uses `PageRouteBuilder` with the standard `transitionsBuilder`
signature. The `anim` argument tracks the route's animation status:
1.0 on full enter, 0.0 on full exit; `transitionsBuilder` runs in
both directions.

If you need *different* visuals on push and pop (not just reverse of
each other), use `secondaryAnimation` inside `transitionsBuilder` or
override `buildTransitions` in a custom route.

## Per-branch transitions

A branch can have its own `pageWrapper`:

```dart
KaiselBranch<ProductRoute>(
  router: _productRouter,
  pageBuilder: /* ... */,
  pageWrapper: (ctx) => switch (ctx.route) {
    ProductDetail() => _CrossFadePage(
      key: ctx.key,
      name: ctx.route.routeName,
      arguments: ctx.route,
      child: ctx.child,
    ),
    _ => MaterialPage(
      key: ctx.key,
      name: ctx.route.routeName,
      arguments: ctx.route,
      child: ctx.child,
    ),
  },
)
```

Useful when a single branch wants a distinct animation style without
imposing it on the rest of the app.

## Common mistakes

| Mistake | Fix |
|:--------|:----|
| Forgetting to fall through to `MaterialPage` | Without a `_` catchall in the switch, the wrapper crashes on unmatched route pairs. Always include `_ => MaterialPage(key: ctx.key, child: ctx.child)`. |
| Dropping `name`/`arguments` on a custom `pageWrapper` | The default wrapper sets `name: ctx.route.routeName` and `arguments: ctx.route`; a custom one that omits them strips route identity, so `RouteObserver`s, analytics screen tracking, and `RouteAware` go blind. Pass both on **every** page you return — custom subclass and `MaterialPage` fallback alike. |
| Pair-matching a transition performed with `set` | `set([X])` collapses the stack to one entry, so `ctx.previous` is `null` and `(A(), B())` never matches. For full-surface swaps (auth, deep-link landing) match on the destination route type, not the pair. |
| Using a custom `Page` subclass for every route, hand-rolling slides that already exist | If the design wants Material's default slide, use `MaterialPage`. Don't reinvent the cupertino/material transitions that the SDK already provides. |
| Reusing the same `LocalKey` across pages | The key passed in `ctx.key` is stable for the route. Don't construct a new `ValueKey` per page build — that breaks state preservation across rebuilds. |
| Trying to gate the transition on width or other runtime context inside the wrapper | The wrapper is called per-page during stack diffing, not on every frame. If you need width-responsive transitions, do that decision inside the `transitionsBuilder` callback (which has the build context), not in the wrapper. |
| Forgetting `reverseTransitionDuration` | If you only set `transitionDuration`, pops use the same duration. Setting a faster `reverseTransitionDuration` is a small polish that makes back navigation feel snappier without rewriting the animation. |
| Hand-rolling fade-via-opacity inside `transitionsBuilder` instead of using `FadeTransition` | `FadeTransition` is cheaper — it short-circuits when opacity is 0 or 1. `Opacity` widgets force a layer in all cases. |
