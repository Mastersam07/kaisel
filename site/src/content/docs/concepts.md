---
title: The mental model
description: The five-minute version of how kaisel thinks — routes are values, the stack is state, everything on screen is a rendering of it.
---

kaisel is one idea applied consistently: **a route is a value**. Everything
the library does follows from taking that seriously. This page is the
five-minute version — with it, every other page in these docs reads as a
variation on a single theme.

## 1. A route is a value

A route isn't a path string that names a screen. It's an object that *is*
the screen's identity — a variant of a sealed class, carrying its
parameters as fields:

```dart
sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

final class Home extends AppRoute { const Home(); }

final class Product extends AppRoute {
  const Product(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}
```

Two consequences fall out immediately. Routes have **equality**
(`Product('42') == Product('42')`), so the router can diff, dedupe, and
restore them. And routes are **exhaustively matchable** — a `switch` over
`AppRoute` fails to compile until every variant is handled, so adding a
screen is a compile error until the whole app knows about it.

## 2. The stack is state — and it's yours

Your navigation history is a `List<AppRoute>`, owned by the router. Not a
hidden framework structure you send events at — a list you can read, and
whose mutations are list operations:

```dart
router.push(const Product('42'));   // [Home(), Product('42')]
router.pop();                       // [Home()]
router.set(const [Home(), Cart()]); // whatever you say it is

expect(router.stack, const [Home()]);  // testable, no widget tree
```

Every mutation flows through the **guard pipeline** — pure functions
`(current, proposed) → allowed` — before it's applied. Because the stack
is a value, you can also *derive* it from app state: write a pure
`stackFor(appState)` and `set` the result when state changes. That's
kaisel's declarative mode; it isn't a separate API, just a consequence of
the model.

## 3. What's on screen is a rendering of the stack

Your `builder` is a projection: it turns the top of the stack into
widgets. kaisel takes this separation seriously, and it's where the
model pays off most:

- **Adaptive layouts** — the *same* stack renders as a phone stack on
  narrow screens and as master-detail, supporting pane, or foldable
  layouts on wide ones. Resizing the window changes the *rendering*, not
  the state: no navigation happens, and the URL doesn't move.
- **Shells and tabs** — each tab branch is *another stack*, running in
  parallel on its own nested Navigator. Switching tabs switches which
  stack is foregrounded; every branch keeps its history. This is
  kaisel's nested routing.
- **The URL** — on the web, the address bar is one more rendering: a
  codec maps the stack to a URL and back. Strings exist in exactly one
  place; everywhere else reasons in typed routes.

## 4. Everything else falls out

Once "the stack is a value that gets rendered" clicks, the rest of the
feature list stops being a list and becomes corollaries:

- **Typed results** — `pushForResult<T>` / `run<T>` return `Future<T?>`
  because a route's completion is data like everything else.
- **Observers see everything** — tab switches and adaptive layout
  changes are stack-visible even when they produce no Navigator event,
  so one registered `NavigatorObserver` reports every navigation.
- **State restoration** — the stack is a value, so it serializes;
  process death restores it.
- **DevTools** — the extension just shows you the stack, live, with
  time-travel. There's nothing else to show.

## Coming from another router?

| You know | In kaisel |
| --- | --- |
| `GoRoute` with a `path` | a sealed route variant (the codec owns paths, if you need URLs) |
| `ShellRoute` / `StatefulShellRoute` | `KaiselBranchedShell` — branches are parallel stacks |
| `redirect:` callbacks | guards: pure `(current, proposed) → stack` |
| `AutoRouter.declarative` / a state-derived routes list | `stackFor(state)` + `router.set(...)` |
| Nested routers (auto_route) | branches, and [modules](/guides/modules/) for feature-owned stacks |
| Parallel routes (web frameworks) | branches (parallel stacks), or adaptive multi-pane (several routes rendered from one stack) |
| `Navigator.push(context, MaterialPageRoute(...))` | `context.router<AppRoute>().push(const Product('42'))` |

## Where next

- [Getting started](/getting-started/) — install to navigating in minutes.
- [Navigation](/guides/navigation/) — the full verb reference: `push`,
  `pop`, `set`, typed results.
- Coming from another router? The [migration guides](/migration/) map
  your current setup piece by piece.
