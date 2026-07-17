---
title: Return a value from a screen
description: Open a picker or form with pushForResult, and get a typed value back when it pops.
---

You want a screen — a picker, a form, a confirmation — to hand a typed
value back to whoever opened it.

## The recipe

Open the screen with `pushForResult<T>` and await:

```dart
final picked = await context.router<AppRoute>()
    .pushForResult<String>(const ColorPicker());

if (picked != null) {
  // The screen popped with a value.
}
```

Inside the screen, pop with the value:

```dart
FilledButton(
  onPressed: () => context.pop('teal'),
  child: const Text('Choose teal'),
)
```

## Notes

- **`null` means dismissed** — the user backed out, or the screen left
  the stack another way. Treat it as a first-class outcome, not an error.
- The screen is a **normal main-stack route**: observers see it, dialogs
  render above it, system back works. If you need a *multi-step* flow
  with its own sub-stack, use [`run<T>`](/guides/modal-flows/) instead —
  same `Future<T?>` shape, different home for the screens.
- A pending result doesn't survive process death (futures can't be
  serialized) — don't gate critical state on one. Details in the
  [navigation reference](/guides/navigation/#pushforresult).
