# Migrating to kaisel

Practical guides for moving an existing Flutter app to kaisel from
another router. These aren't sales pitches and they aren't lists of
grievances against the routers you're leaving behind — the rationale
for choosing kaisel lives in the
[Routes as Values][article] article. These guides are the work that
comes after that decision: what translates, what doesn't, and what
your migration branch will actually look like.

[article]: https://medium.com/@codefarmer/flutter-routes-as-values-089476ad4d5b

## Available guides

| Guide                                       | Best for                                              | Effort                  |
| ------------------------------------------- | ----------------------------------------------------- | ----------------------- |
| [`from-go-router.md`](from-go-router.md)    | Apps using `GoRouter` with string paths               | ~3–4 days, 30 screens   |
| [`from-auto-route.md`](from-auto-route.md)  | Apps using `@AutoRouterConfig` with `build_runner`    | ~2 days, 30 screens     |
| [`from-navigator.md`](from-navigator.md)    | Apps on Flutter's `Navigator` — imperative `push`, named routes, or the Router/Pages API (2.0) | ~2–4 days, 30 screens (less from named/2.0) |

## Which guide is for you

You're on **go_router** if your route table is a list of `GoRoute`
objects with `path:` strings, your auth logic lives in a global
`redirect:` callback, and your tabbed shells use `ShellRoute` or
`StatefulShellRoute`. The migration is mostly a conceptual shift:
URLs stop being canonical and become a serialization layer that a
codec produces from the typed stack. Plan three to four days for a
medium-sized app.

You're on **auto_route** if your screens are annotated with
`@RoutePage()`, your routes are codegen-produced classes, and your
build pipeline includes a `build_runner` step. The migration is
mostly mechanical — sealed types and a switch take the place of the
annotations and the generated table. The largest material win is
that `build_runner` leaves the project. Plan around two days for a
medium-sized app.

You're on **Navigator** if you call `Navigator.push` with
`MaterialPageRoute` directly, or use named routes
(`MaterialApp(routes:)`, `pushNamed`, `onGenerateRoute`). Named routes
are the gentler on-ramp — you already have a centralized table to
transcribe into a sealed type — while scattered imperative `push` calls
need discovering first. The headline win either way is typed arguments
and an exhaustive `switch` replacing `Object?` casts and stringly-typed
names. A codec is only needed if those routes doubled as web URLs. And if
you hand-rolled **Navigator 2.0** (your own `RouterDelegate` + `Pages` list),
you've already made the declarative shift — that migration is mostly deleting
the boilerplate kaisel provides.

If you're on both (different parts of the same codebase, or a
half-finished migration between them already), pick the one with
more routes attached to it and tackle that first; the other tends to
fall in line once the page builder and guard pipeline are in place.

## General principles that apply to both

**Big bang, not incremental.** Two routers don't compose well on the
same Navigator. The recommendation in both guides is: pick a week,
branch from main, do the rewrite, regression-test, ship. If you
can't afford the branch, you can't afford the migration yet — wait
for a quieter sprint.

**Sealed routes are the model; URLs are a serialization layer.** In
both source libraries the URL is (or codegens up to) the primary
representation. In kaisel the typed `sealed class AppRoute` is
primary and URLs come out of a codec. This inversion is the single
piece of work that has to happen mentally before the rest of the
migration makes sense.

**Guards are a pipeline, not callbacks on routes.** Whichever guard
mechanism you came from (go_router's global `redirect:`, auto_route's
`AutoRouteGuard` classes), kaisel expresses cross-cutting concerns
as pure functions composed in a list. Each guard sees the current and
proposed stacks and returns the actual stack. This is more expressive than a
callback that returns a URL but it asks you to think about the
problem in stack terms.

**Per-branch state preservation is the default.** If your old shell
preserved tab state via opt-in (`StatefulShellRoute` in go_router,
`AutoTabsRouter` with `usePagesViewRouting` in auto_route), kaisel
does it by default. If your old shell *didn't* preserve state, your
app will behave differently after migration. Decide whether that's
the new desired behavior or whether you need to reset stacks
explicitly on switch.

## What kaisel doesn't yet do at parity

Both guides flag these in their own "what doesn't translate" sections;
worth surfacing here too so you can decide before reading either
guide.

- **Browser back integration on the web.** Works via the codec, but
  less polished than go_router's native integration. Test carefully
  on a migration branch if web is your primary platform.
- **Pre-built page transitions.** No library of named transitions
  (`SlideFromBottom`, `Fade`, etc.). You wire transitions via the
  `pageWrapper` mechanism (see the
  [`main_transitions.dart`](../../example/lib/main_transitions.dart)
  example).

See each package's [`CHANGELOG.md`](../../CHANGELOG.md) for current status.

## Reference examples

The
[`example/`](../../example) folder contains several small apps that
demonstrate the patterns these guides describe in working form:

- [`main.dart`](../../example/lib/main.dart) — minimal router setup with
  a sealed route hierarchy and a codec.
- [`main_adaptive.dart`](../../example/lib/main_adaptive.dart) —
  adaptive master-detail without a shell, useful for understanding
  the absorbing-pages model in isolation.
- [`main_transitions.dart`](../../example/lib/main_transitions.dart) —
  route-pair transitions via the `pageWrapper` mechanism.
- [`main_nested_flows.dart`](../../example/lib/main_nested_flows.dart) —
  typed modal flows with LIFO completion (a payment flow opening an
  add-card flow on top of itself).
- [`main_shell_adaptive.dart`](../../example/lib/main_shell_adaptive.dart) —
  branched shell with adaptive layout inside one branch.
- [`main_lazy_shell.dart`](../../example/lib/main_lazy_shell.dart) —
  lazy + deferred (code-split) shell branches (the `StatefulShellRoute` /
  `AutoTabsScaffold` lazy-loading target).
- [`main_auth_redirect.dart`](../../example/lib/main_auth_redirect.dart) —
  redirect to login from a guard, then continue to the intended destination.
- [`main_media_cataloguer.dart`](../../example/lib/main_media_cataloguer.dart) —
  end-to-end desktop app combining auth state machine, branched
  shell, per-branch typing, nested stacks, and adaptive master-detail.

If you get stuck on how a specific construct translates, scanning
the relevant example is often faster than searching documentation.

## Asking for help

File an issue at the [kaisel repo](https://github.com/Mastersam07/kaisel)
with the construct you can't figure out how to translate. Migration
questions are the highest-value GitHub conversations to have right
now — they inform what the guides should cover next and help shape
the API as it firms up toward v1.0.
