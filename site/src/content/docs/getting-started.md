---
title: Getting started
description: Install kaisel, declare a sealed route type, and wire it into MaterialApp.router — three steps, no codegen.
---

kaisel is a Dart 3-native router: your routes are a sealed class hierarchy,
your screens are an exhaustive `switch`, and the navigation stack is a plain
`List` of route values.

## Install

```sh
flutter pub add kaisel
```

kaisel supports Flutter 3.24+ and requires Dart 3.

## 1. Declare your route type

```dart
sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

final class Home extends AppRoute { const Home(); }

final class ProductDetail extends AppRoute {
  const ProductDetail(this.id);
  final String id;

  @override
  List<Object?> get props => [id];
}
```

No-field variants get equality automatically (`Home() == Home()`). Variants
with fields override `props`.

## 2. Wire it up

Bundle the router into a `KaiselRouterConfig` and hand it to
`MaterialApp.router` — no `StatefulWidget`, no manual delegate or parser:

```dart
final _config = KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  builder: (context, route) => switch (route) {
    Home() => const HomeScreen(),
    ProductDetail(:final id) => ProductDetailScreen(id: id),
  },
);

void main() => runApp(MaterialApp.router(routerConfig: _config));
```

Add a variant and the `switch` fails to compile until you handle it. That's
the entire point.

## 3. Navigate

```dart
context.router<AppRoute>().push(const ProductDetail('42'));
context.pop();

// Typed results:
final picked = await context.pushForResult<String>(const ColorPicker());
```

## Where next

- [Tutorial: your first app](/tutorial/) — build a small app end to end
  in about twenty minutes: navigation, a typed result, and a guard.
- [The mental model](/concepts/) — five minutes on how kaisel thinks;
  every other page assumes it.
- [Navigation](/guides/navigation/) — the full core guide: stacks, typed
  results, and imperative navigation outside the tree.
- [Shells & tabs](/guides/shells/) — bottom-nav with per-tab state.
- [Guards](/guides/guards/) — auth redirects as pure functions.
- [URLs & deep linking](/guides/urls-and-deep-linking/) — make the app
  URL-addressable when you need it.
- Coming from another router? Start at the
  [migration overview](/migration/) — guides for go_router, auto_route,
  and Navigator, with effort estimates.
