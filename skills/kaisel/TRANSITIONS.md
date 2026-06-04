# Transitions

Reference for `KaiselPageWrapper`, `KaiselPageWrapperContext`, and the
custom `Page<T>` subclasses you'll write to drive specific animations.
Use this when default `MaterialPage` slide-on-push isn't what the
design calls for — fade between auth states, slide-up modally for
sheets, cross-fade between sibling details, etc.

## The model

By default, `KaiselRouterDelegate` wraps every route's widget in a
`MaterialPage` — slide-on-push, slide-on-pop. To customise, pass a
`pageWrapper` to the delegate. The wrapper receives a
`KaiselPageWrapperContext<R>` describing what's being added or
replaced, and returns a `Page<Object?>` subclass that determines the
transition.

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

## Quick reference

| Type | Purpose |
|:-----|:--------|
| `KaiselPageWrapper<R>` | `Page<Object?> Function(KaiselPageWrapperContext<R>)`. Passed to the delegate's `pageWrapper`. |
| `KaiselPageWrapperContext<R>` | `route`, `child`, `key`, `position`, `stackLength`, `previous`. |
| `Page<T>` | Flutter's `Page` API — you subclass this for each transition style. |
| `PageRouteBuilder<T>` | Flutter's low-level route builder for custom transitions. Constructed inside your `Page` subclass's `createRoute`. |

## The canonical pattern

### 1. A custom `Page` for the transition style

```dart
class _FadePage<T> extends Page<T> {
  const _FadePage({required LocalKey super.key, required this.child});
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
  const _SlideUpPage({required LocalKey super.key, required this.child});
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
  return switch ((ctx.previous, ctx.route)) {
    // Login ↔ Shell: cross-fade in both directions.
    (ShellHost(), LoginRoute()) ||
    (LoginRoute(), ShellHost()) =>
      _FadePage<Object?>(key: ctx.key, child: ctx.child),

    // Settings slides up from the bottom whenever it's opened.
    (_, Settings()) =>
      _SlideUpPage<Object?>(key: ctx.key, child: ctx.child),

    // Default: MaterialPage slide.
    _ => MaterialPage<Object?>(key: ctx.key, child: ctx.child),
  };
}
```

### 3. Pass it to the delegate

```dart
_delegate = KaiselRouterDelegate<AppRoute>(
  router: _router,
  builder: /* ... */,
  pageWrapper: _appPageWrapper,
);
```

## Pattern shapes you'll write

### Destination-only

"Whenever this route appears on top, use this transition." Match on
the route only:

```dart
(_, Settings()) => _SlideUpPage(/* ... */),
(_, About()) => _FadePage(/* ... */),
```

### Route-pair

"Only fade when going from A to B." Match the tuple:

```dart
(LoginRoute(), ShellHost()) => _FadePage(/* ... */),
(ShellHost(), LoginRoute()) => _FadePage(/* ... */),
```

Two arms, one per direction. Flutter's Navigator handles forward vs.
reverse direction automatically — you just need to declare *that*
this pair uses the fade style.

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
    ProductDetail() => _CrossFadePage(key: ctx.key, child: ctx.child),
    _ => MaterialPage(key: ctx.key, child: ctx.child),
  },
)
```

Useful when a single branch wants a distinct animation style without
imposing it on the rest of the app.

## Common mistakes

| Mistake | Fix |
|:--------|:----|
| Forgetting to fall through to `MaterialPage` | Without a `_` catchall in the switch, the wrapper crashes on unmatched route pairs. Always include `_ => MaterialPage(key: ctx.key, child: ctx.child)`. |
| Using a custom `Page` subclass for every route, hand-rolling slides that already exist | If the design wants Material's default slide, use `MaterialPage`. Don't reinvent the cupertino/material transitions that the SDK already provides. |
| Reusing the same `LocalKey` across pages | The key passed in `ctx.key` is stable for the route. Don't construct a new `ValueKey` per page build — that breaks state preservation across rebuilds. |
| Trying to gate the transition on width or other runtime context inside the wrapper | The wrapper is called per-page during stack diffing, not on every frame. If you need width-responsive transitions, do that decision inside the `transitionsBuilder` callback (which has the build context), not in the wrapper. |
| Forgetting `reverseTransitionDuration` | If you only set `transitionDuration`, pops use the same duration. Setting a faster `reverseTransitionDuration` is a small polish that makes back navigation feel snappier without rewriting the animation. |
| Hand-rolling fade-via-opacity inside `transitionsBuilder` instead of using `FadeTransition` | `FadeTransition` is cheaper — it short-circuits when opacity is 0 or 1. `Opacity` widgets force a layer in all cases. |
