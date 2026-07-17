---
title: Redirect to login (and continue after)
description: Gate protected routes with a guard, then land the user where they were headed once they sign in.
---

Some routes need a signed-in user. When a logged-out user heads to one,
show login instead — and after they sign in, continue to where they were
going, not to a generic home screen.

## The recipe

Mark protected routes with an interface:

```dart
abstract interface class RequiresAuth {}

final class Payment extends AppRoute implements RequiresAuth {
  const Payment();
}
```

Write a guard that stashes the intended stack and redirects:

```dart
List<AppRoute>? _intended;

KaiselGuard<AppRoute> authGuard(ValueListenable<bool> loggedIn) {
  return (current, proposed) {
    final needsAuth = proposed.any((r) => r is RequiresAuth);
    if (needsAuth && !loggedIn.value) {
      _intended = proposed;
      return const [Login()];
    }
    return proposed;
  };
}
```

Register it: `KaiselRouterConfig(guards: [authGuard(_loggedIn)], ...)`.

After a successful login, replay the stash:

```dart
_loggedIn.value = true;
context.router<AppRoute>().set(_intended ?? const [Home()]);
_intended = null;
```

## Why this works so cleanly

The intended destination is plain data — a `List<AppRoute>` — so the
*whole* stack is reconstructed, not just the final screen: if the user
was headed to `[Home(), Cart(), Payment()]`, they land on Payment with
Cart beneath it and back behaving correctly. The same guard handles deep
links into protected routes with zero extra code.

## Notes

- Guards don't run on system back (the pop has already animated by the
  time the router hears about it). For "force back to login on logout,"
  listen to your auth state and call `router.set(const [Login()])`
  directly.
- The guard is a pure function — unit test it with two lists and no
  widgets. See the [guards reference](/guides/guards/).
- Runnable version:
  [`main_auth_redirect.dart`](https://github.com/Mastersam07/kaisel/blob/dev/packages/kaisel/example/lib/main_auth_redirect.dart).
