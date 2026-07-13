# kaisel Roadmap

kaisel is a Dart 3-native router built on sealed routes, exhaustive pattern matching, and a stack-as-value model. The thinking behind that design — why a route is a value, not a string — is laid out in [Flutter Routes as Values](https://medium.com/@codefarmer/flutter-routes-as-values-089476ad4d5b). This roadmap outlines where the project stands, what's planned before the 1.0 stable release, and what's intentionally out of scope.

It's directional, not a set of dated commitments — items land when they're ready, and priorities shift with feedback. If something here matters to you, or is missing, open an issue; that's the signal we weigh.

## Status

The core surface is complete and in production use. Grouped by capability:

- **Routing core** — sealed value routes, exhaustive page builders, a guard pipeline of pure functions, typed results (`pushForResult<T>`), and modal flows with typed returns (`run<T>`).
- **Shells and modules** — per-tab typed shells (`KaiselBranchedShell`), lazy and code-split branches, and composable, URL-addressable modules.
- **Adaptive layouts** — one stack, many renderings via the absorption primitive: master-detail, supporting pane, three-pane, and foldable layouts, all driven by the same router state.
- **State restoration** — survive OS process-death through Flutter's `RestorationManager`, with a codec-less path for apps that don't use URLs.
- **DevTools extension** — a zero-integration inspector of the stack, shells, modules, flows, guard trace, and codec/URL, with time-travel and a Problems panel.
- **Android predictive back** (opt-in, preview) — shell branches follow the OS back gesture when enabled via `androidPredictiveBack`. Being validated on-device ahead of 1.0 (see below).

## Toward 1.0

1.0 marks an **API freeze** — a commitment to the current surface — rather than a feature milestone. The functional surface is in place, and production use plus community feedback have exercised it without surfacing shape problems. One item remains before the freeze:

- **Validate Android predictive back on-device.** The behaviour behind the opt-in `androidPredictiveBack` flag is covered by widget tests, but what it targets — the OS back-gesture preview — is compositor-level and can only be confirmed on a real Android 13+ device. We're doing that before committing. (The default was settled in dev.3: opt-in, off by default.)

## Under consideration

Directions we're weighing, roughly by interest:

- **Codec ergonomics.** URLs are produced by a hand-written `encode`/`decode`. We're exploring helpers that shrink that boilerplate without reintroducing code generation — the most common piece of feedback we receive.
- **Context-aware guards.** Guards are pure `(current, proposed)` transforms today, testable without a widget tree. An optional Flutter-layer guard that receives a `BuildContext` — for idiomatic `context.read<T>()` state access — could sit alongside the pure default, trading dry-run testability for convenience. It would be additive, never the default.
- **Custom predictive-back animations.** kaisel's opt-in predictive back uses Flutter's built-in animation (the standard Android shrink-and-peek). There's no hook to supply your *own* animation driven by the back gesture — auto_route offers this by vendoring Flutter's private gesture detector, and kaisel could do the same. Niche and maintenance-heavy, so gated on real demand.
- **DevTools polish.** Transitions-log replay on reconnect, guard dry-run against a hypothetical stack, and the remaining write commands.
- **Primary constructors.** No library change required — route classes get shorter for free once you're on Dart 3.13. We'll adopt them in docs and examples when that SDK is widely available, without raising kaisel's minimum SDK.

## Not planned

Deliberate non-goals, with the reasoning — so it's clear what kaisel won't become:

- **Code generation.** kaisel is codegen-free by design; routes stay hand-written sealed classes. Reach for `freezed` per route if you want it — kaisel never forces a build step.
- **A bundled transition library.** The `pageWrapper` API lets you write any transition; a "common transitions" pack doesn't earn its way into the core.
- **A dedicated analytics API.** Observers registered via `observers:` see every navigation — including adaptive in-place changes, which kaisel reports to them — and `onTransition` exposes each change as values. Together with `routeName`, screen tracking is covered without a dedicated layer.
- **Persistence beyond restoration.** Offline mode, sync, and background fetch are app concerns, not router concerns.
- **Automatic adaptive replace-top.** Whether a same-type push means "swap this pane" (master-detail) or "drill deeper" (a comment thread) is app intent the router can't infer, so it stays an explicit choice between `push` and `pushOrReplaceTop`.

---

This document evolves as things crystallize. Dates and ordering are indicative, not guarantees.
