---
title: Deep link into a screen
description: Give the app URLs — a codec maps web addresses and deep links to typed route stacks, in one place.
---

You want `/products/42` to open the product screen — from a shared link,
a web address bar, or an OS deep link — with a sensible back stack
underneath it.

## The recipe

Write a codec: two functions between stacks and URLs. This is the *only*
place URL strings exist in a kaisel app:

```dart
class AppCodec extends KaiselStackCodec<AppRoute> {
  const AppCodec();

  @override
  Uri encode(List<AppRoute> stack) => switch (stack.last) {
    Home() => Uri(path: '/'),
    ProductDetail(:final id) => Uri(path: '/products/$id'),
    Settings() => Uri(path: '/settings'),
  };

  @override
  List<AppRoute>? decode(Uri uri) => switch (uri.pathSegments) {
    [] || [''] => const [Home()],
    ['products', final id] => [const Home(), ProductDetail(id)],
    ['settings'] => const [Home(), Settings()],
    _ => null,
  };
}
```

Register it on the config:

```dart
final _config = KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  codec: const StackToConfigCodec(AppCodec()),
  builder: ...,
);
```

## Notes

- **`decode` returns a whole stack**, not one screen — that's how a
  cold-started deep link lands on the detail *with a coherent back
  history* (`[Home(), ProductDetail('42')]` means back goes home, not
  out of the app).
- Return `null` from `decode` for URLs you don't recognise — the router
  falls back to the configured `fallback` stack (your `initial` by
  default) instead of crashing.
- `encode` is exhaustive over your sealed routes, so adding a route
  without deciding its URL is a compile error — the same
  compiler-as-checklist that protects your builder.
- URLs are opt-in: apps without the `codec:` parameter never touch
  strings at all. Full story (nested shells, modules, restoration) in
  the [URLs & deep linking reference](/guides/urls-and-deep-linking/).
