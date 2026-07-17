# Guards

You need to protect routes: send logged-out users to login, gate
features behind flags or entitlements, or stop navigation away from
unsaved work.

Reference for `KaiselGuard<R>` and the guard pipeline. Use guards
when something cross-cutting needs to influence what the stack
becomes — auth gating, feature flags, entitlement checks, dirty-form
prompts, modal-blocking patterns. Guards are kaisel's answer to
go_router's `redirect:` callback and auto_route's `AutoRouteGuard`.

## The model

A guard is a function from a proposed stack to the actual stack. Every
mutation through the router (push, pop, set, replaceTop,
pushOrReplaceTop, run) runs through the configured guards before the
mutation takes effect.

The pipeline shape matters:

- Multiple guards compose as a list. Each receives the output of the
  previous.
- Order is meaningful — an auth guard that gates everything else
  should run *before* a feature-flag guard that gates specific routes,
  not after.
- Guards see *both* the current stack and the proposed stack, so they
  can make decisions based on transitions, not just destinations.

## The signature

```dart
typedef KaiselGuard<R extends KaiselRoute> = FutureOr<List<R>> Function(
  List<R> current,
  List<R> proposed,
);
```

Takes the current stack and the proposed stack. Returns either the
proposed stack (allow), a transformed stack (redirect), or `current`
(reject — equivalent to canceling the mutation). The `FutureOr` allows
async guards that need to consult network state, secure storage, etc.

## The canonical pattern

```dart
List<AppRoute> authGuard(List<AppRoute> current, List<AppRoute> proposed) {
  final goingToAuthScreen = proposed.any((r) => r is Login);
  final isLoggedIn = authService.isLoggedIn;

  if (goingToAuthScreen) {
    // Always allow navigation to the Login route itself.
    return proposed;
  }
  if (!isLoggedIn) {
    // Force-redirect any mutation to the login screen.
    return [const Login()];
  }
  return proposed;
}

final router = KaiselRouter<AppRoute>(
  initial: authService.isLoggedIn ? const Home() : const Login(),
  guards: [authGuard],
);
```

Three things to notice:

1. **The guard is a pure function.** It reads service state, makes a
   decision, returns a stack. It doesn't call `router.push(...)` — it
   *is* the function the router consults before doing its own push.
2. **The return value replaces the proposed stack entirely.** This is
   more expressive than go_router's redirect, which can only return a
   single URL: a guard can prepend, append, slice, or rewrite the
   stack.
3. **Allowing navigation is just `return proposed`.** The default
   semantic is "let it through" — guards are filters that selectively
   intervene, not validators that explicitly approve.

## Composing multiple guards

Multiple cross-cutting concerns compose as a list. Each runs in order,
each receives the previous guard's output:

```dart
KaiselRouter<AppRoute>(
  initial: const Home(),
  guards: [
    authGuard,         // gates everything behind sign-in
    featureFlagGuard,  // gates specific routes behind feature flags
    entitlementGuard,  // gates premium routes behind entitlement
  ],
);
```

Order is meaningful. The auth guard runs first because every other
check assumes the user is signed in. The feature-flag guard runs next
because flags can hide routes that the user is otherwise entitled to
see. The entitlement guard runs last because it operates on the
specific routes that survived the previous filters.

## Common guard patterns

### Auth gating

The auth guard above. Force-redirect to login if not signed in;
otherwise let through.

### Feature-flag gating

Hide specific routes when their flag is off:

```dart
List<AppRoute> featureFlagGuard(
  List<AppRoute> current,
  List<AppRoute> proposed,
) {
  final hidden = proposed.where((r) {
    if (r is BetaFeature && !flags.betaEnabled) return true;
    return false;
  });
  if (hidden.isEmpty) return proposed;

  // The proposed stack contains a route that's gated off. Drop it.
  return proposed.where((r) => !hidden.contains(r)).toList();
}
```

The pattern: if the proposed stack contains gated routes, filter them
out rather than redirecting wholesale. The user lands on the last
non-gated route in the stack.

### Entitlement gating

Like feature flags but per-user, often async:

```dart
Future<List<AppRoute>> entitlementGuard(
  List<AppRoute> current,
  List<AppRoute> proposed,
) async {
  for (final route in proposed) {
    if (route is PremiumFeature) {
      final entitled = await entitlements.has('premium');
      if (!entitled) {
        return [const Home(), const Upgrade()];
      }
    }
  }
  return proposed;
}
```

`FutureOr` lets the guard `await` an entitlements service. The router
waits for the future before committing the mutation.

### Dirty-form prompt (on pop)

A pop that would leave a dirty form should ask first. Guards see pops
too:

```dart
List<AppRoute> dirtyFormGuard(
  List<AppRoute> current,
  List<AppRoute> proposed,
) {
  final isPop = proposed.length < current.length;
  final leavingForm = current.last is FormScreen && proposed.last is! FormScreen;
  if (isPop && leavingForm && formIsDirty) {
    // Reject the pop — UI shows a confirmation prompt instead.
    showDirtyFormDialog();
    return current;  // unchanged stack = no mutation
  }
  return proposed;
}
```

### Deep-link sanitisation

When a deep link tries to land at a route that requires arguments not
present in the URL:

```dart
List<AppRoute> deepLinkSanitiser(
  List<AppRoute> current,
  List<AppRoute> proposed,
) {
  // Drop routes that can't sensibly be reached via deep link.
  return proposed.where((r) {
    if (r is ContextDependentRoute && current.isEmpty) return false;
    return true;
  }).toList();
}
```

## Per-flow guards

Modal flows can have their own guards independent of the main
router's guards. Pass `flowGuards` when calling `run`. `flowGuards` are
typed to the router's route type, so use the typed `context.router<R>()`
form here (the terse `context.run` covers the no-guards case):

```dart
final result = await context.router<AppRoute>().run<String>(
  const PaymentFlow(),
  flowGuards: [
    (current, proposed) {
      // Pop confirmation while a payment is in flight.
      if (paymentInFlight && proposed.length < current.length) {
        return current;
      }
      return proposed;
    },
  ],
);
```

The flow's sub-router runs these on its own stack mutations. They
don't see the main stack.

## Comparison with the source libraries

**go_router's redirect** is a callback that returns `String?` (a
path) or `null` (allow). It runs on the destination, not on the
transition. Multiple redirects compose by re-running the callback on
the redirect target.

**auto_route's AutoRouteGuard** is a class with
`onNavigation(resolver, router)` that calls `resolver.next(allowed)`
or pushes a redirect imperatively. Attached per route.

**kaisel's KaiselGuard** is a pure function on the whole stack,
registered globally on the router. The difference matters most when
the cross-cutting concern is *about* transitions (dirty-form pops,
auth-state changes, modal-blocking), not just about destinations.
Returning a stack instead of a single route is also more expressive:
a guard can prepend a step ("you must verify your email first") or
append one ("after this, show the welcome tour") without the calling
code knowing.

## Common mistakes

| Mistake | Fix |
|:--------|:----|
| Mutating the router from inside a guard | Don't. Guards are pure functions. Calling `router.set(...)` inside a guard causes recursion. Return the desired stack from the guard instead. |
| Returning a stack that the router can't render (missing variants from the page builder) | The guard's return value is what the page builder will receive. Make sure every route in the returned stack has a matching `switch` arm. |
| Forgetting to allow navigation to the auth screen itself in an auth guard | If `goingToAuthScreen` doesn't short-circuit, the auth guard force-redirects to login *while already navigating to login* — infinite redirect. Always allow the auth route through explicitly. |
| Ordering guards so feature flags run before auth | A feature flag check on a route the user isn't allowed to see is wasted work and can leak state. Run auth first. |
| Async guards that don't propagate failures | If the entitlement service throws, the guard should fall back to a safe stack (drop the gated routes, navigate to an error route, etc.), not propagate the error and break the mutation entirely. |
| Holding mutable state inside a guard closure | Guards are called on every mutation. Stateful closures lead to subtle inconsistencies. Read state from services on each call; don't cache. |
