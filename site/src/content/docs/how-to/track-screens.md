---
title: Track screens in analytics
description: Register a standard NavigatorObserver once — it sees every navigation, including tab switches and adaptive changes.
---

You want every screen view in your analytics — Firebase, Sentry,
anything that speaks `NavigatorObserver`.

## The recipe

```dart
final _config = KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  observers: () => [
    FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
  ],
  builder: ...,
);
```

That's the entire integration. The builder is called once per navigator
(main stack, each tab branch, each module and flow), so every navigator
gets its own fresh observer instance — which is what `NavigatorObserver`
requires — and together they see the whole app.

## What you get that other routers don't report

kaisel reports **every navigation** to your observers, including two
kinds that produce no Navigator event elsewhere:

- **Tab switches** — switching branches reports a `didReplace` of the
  old visible screen by the new one.
- **Adaptive in-place changes** — when a wide-screen master-detail swaps
  the detail pane in place, observers get kind-matched events
  (`didPush`/`didPop`/`didReplace`) even though no route transition
  animated.

Every navigation. One observer. Zero wiring.

## Custom tracking with values

If you'd rather track from route *values* than observer events, use
`onTransition` — every committed stack change as data:

```dart
KaiselRouterConfig<AppRoute>(
  onTransition: (from, to) {
    analytics.logScreenView(screenName: to.last.routeName);
  },
  ...
);
```

## Notes

- The `observers:` builder must return **new instances each call** — an
  observer belongs to exactly one navigator. Don't share one instance.
- **Don't synchronously update widget-bound state from observer
  callbacks.** A newly mounted navigator (a flow opening, a tab's first
  build) dispatches its initial notifications *during build* — mutating a
  `ValueNotifier` a `ValueListenableBuilder` watches will throw
  markNeedsBuild-during-build. Analytics calls are fine (they're I/O);
  for UI-bound state, defer with a microtask — it can never run mid-build,
  and from a tap it still lands before the next frame renders:

  ```dart
  void _add(String entry) =>
      scheduleMicrotask(() => _log.value = [..._log.value, entry]);
  ```
- Using a custom `pageWrapper`? Forward `name:` and `arguments:` on every
  page you return, or observers go blind — see
  [Transitions](/guides/transitions/).
