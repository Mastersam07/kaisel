---
title: Drive the stack from app state
description: The declarative pattern — derive the whole stack from your state with a pure function, and set it on changes.
---

You want the navigation stack to be a function of your app state — what
`AutoRouter.declarative` or a state-derived routes list does in other
routers.

## The recipe

Write a pure function from state to stack, and `set` its result whenever
the state changes:

```dart
List<AppRoute> stackFor(AppModel m) => [
  const Home(),
  for (final doc in m.openDocuments) DocumentRoute(doc.id),
  if (m.showOnboarding) const Onboarding(),
];

model.addListener(() => router.set(stackFor(model)));
```

That's the whole pattern. `router` is `yourConfig.router` if you're using
`KaiselRouterConfig` — the context-free handle for navigation outside the
widget tree.

## Notes

- **Same minimal-change result** as rebuild-and-diff routers: pages are
  keyed by route value, so routes present in both old and new stacks keep
  their page state; only the difference animates.
- Derivation happens on **state events, not widget rebuilds** — no
  rebuild-loop hazards, and `stackFor` is unit-testable with no widget
  tree.
- Every derived stack still flows through the
  [guard pipeline](/guides/guards/) — deriving doesn't bypass protection.
- More in the [navigation reference](/guides/navigation/#declarative-state-driven-stacks).
