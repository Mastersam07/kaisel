# Navigation methods

You want to move between screens: open a detail page, come back,
return a value to the caller, or swap the whole stack at once.

Reference for choosing between `push`, `pop`, `set`, `replaceTop`,
`pushOrReplaceTop`, and `run<T>`. Each method mutates the stack
differently and is appropriate for a different situation.

## Two ways to call them

Every verb has two surfaces. Lead with the typed one:

- **Typed `context.router<R>().<verb>` — the idiomatic default.**
  `context.router<R>()` resolves the nearest router of route family `R`,
  and the verb is then a compile-checked call against that family: a route
  from the wrong family is a **compile error**, caught before you run.
  `context.router<R>()` also hands you the actual `KaiselRouter<R>`, so the
  full surface (`stack`, `pop`, `replaceTop`, `run`, …) is right there. This
  is the form to reach for by default — it's the one the type system backs.
- **Terse `context.<verb>` — a deliberate convenience.** `context.push(...)`,
  `context.pop()`, `context.replaceTop(...)`, `context.pushOrReplaceTop(...)`,
  `context.set(...)`, `context.run<T>(...)` drop the `<R>` and resolve the
  *nearest* router whose route type **accepts** the argument, walking up the
  tree at runtime. You trade the compile-time family check for brevity: a
  wrong-family route now throws at **runtime** instead of failing to compile.
  Reach for it when the terseness clearly earns that trade — e.g. a
  single-router screen, where there's no wrong family to get wrong.

`push`/`pop`/`replaceTop`/`pushOrReplaceTop`/`set` are non-generic on the
terse surface; only `run<T>` carries a result type either way. The sections
below show the typed form first.

## Quick reference

| Method | Stack effect | Returns | Use when |
|:-------|:-------------|:--------|:---------|
| `push(route)` | Adds to top | `Future<void>` | Going forward to a new screen |
| `pushForResult<T>(route)` | Adds to top | `Future<T?>` (screen result) | A main-stack screen that returns a value |
| `pop([result])` | Removes top | `Future<bool>` (success) | Going back; respects guards, optionally returns `result` |
| `back()` / `historyGo(delta)` | History-aligned back | `Future<bool>` (navigated) | Browser Back/Forward should mirror multi-level back on the web |
| `replaceTop(route)` | Removes top, pushes new | `Future<void>` | Swap current screen in place (no back history) |
| `pushOrReplaceTop(route)` | Push if top differs in runtime type; replace if same | `Future<void>` | Adaptive master-detail; tab-style in-place updates |
| `set(routes)` | Replaces entire stack | `Future<void>` | Auth state transitions, deep-link landing |
| `run<T>(flow)` | Opens a typed modal flow | `Future<T?>` (flow result) | Modal sub-flows (payment, wizard, picker) |

`pushForResult<T>` and `run<T>` both return `Future<T?>`. The difference is
*where the screen lives*: `pushForResult` keeps it on the main stack (a normal
route — observed, with root dialogs above it, normal back); `run<T>` lifts a
multi-screen flow into its own sub-router. See [MODAL_FLOWS.md](./MODAL_FLOWS.md)
for choosing between them.

All methods run through the guard pipeline (if configured) before
applying. A guard can reject or transform any proposed stack.

## push

```dart
context.router<AppRoute>().push(const ProductDetail('sku-42'));
// Terse convenience (runtime-resolved):
context.push(const ProductDetail('sku-42'));
```

Adds the route on top of the current stack. The previous top stays
below — pop returns to it. This is standard forward navigation.

**Use for:** Tapping a list item, opening a detail page, entering a
sub-screen.

**Notes:**

- `push` is *not* the right call inside an adaptive master-detail
  scenario where the top is already a sibling detail variant. Use
  `pushOrReplaceTop` there — see [ADAPTIVE.md](./ADAPTIVE.md).
- `push` is *not* the right call for a typed modal flow. Use `run<T>`
  — see [MODAL_FLOWS.md](./MODAL_FLOWS.md).
- To get a value *back* from the pushed screen, use `pushForResult<T>`
  (below) — `push` returns `Future<void>`, which settles when the
  navigation is applied, not when the screen pops.

## pushForResult

```dart
final picked = await context.router<AppRoute>().pushForResult<String>(
  const ColorPicker(),
);
// Terse convenience (runtime-resolved):
final picked = await context.pushForResult<String>(const ColorPicker());
if (picked != null) {
  // The screen popped with a value.
} else {
  // Dismissed without one.
}
```

Pushes the route onto the main stack like `push`, but returns a
`Future<T?>` that resolves when that pushed screen leaves the stack. The
screen returns its value by popping with one — `context.pop(picked)`.

**Use for:** A picker, a form, a confirm screen — anywhere a screen on
the **main stack** should hand a value back to its caller, and should
otherwise behave like a normal screen (a shared `RouteObserver` sees it,
a root-navigator dialog renders above it, system back works normally).

**Notes:**

- The future resolves with `null` if the screen is popped without a value
  (`context.pop()`), replaced off the stack by `set` / `replaceTop`,
  removed by system back, or the router is disposed — treat `null` as
  "dismissed", a first-class outcome.
- **A pending result does not survive process-death restoration.** A
  `Future` can't be serialized, so if the OS kills and relaunches the app
  while you're awaiting one, that await is gone with the old isolate (the
  result is lost, not delivered). An in-process stack replacement resolves
  the awaiter with `null` rather than hanging. Don't gate critical state on
  a result that must outlive a kill — persist it.
- `pushForResult<T>` vs `run<T>`: both return `Future<T?>`. Use
  `pushForResult` for a single screen on the main stack; use `run<T>`
  when you want a multi-step flow in its own sub-router (its own stack,
  nesting, an overlay layer). See [MODAL_FLOWS.md](./MODAL_FLOWS.md).
- The pushed screen completes with `context.pop(value)` — the same `pop`
  you use for back, with the value as its argument.

## pop

```dart
final didPop = await context.router<AppRoute>().pop();
// Return a value to a pushForResult awaiter:
await context.pop(selectedId);
// Terse convenience (runtime-resolved):
final didPop = await context.pop();
```

Removes the top entry. Returns `true` if the pop happened, `false` if
the stack was already at one entry (you can't pop the root) or if a
guard blocked the mutation. Pass an optional `result` to hand a value
back to a matching `pushForResult<T>` awaiter.

**Use for:** Back buttons, "cancel" actions, and returning a value from
a screen opened with `pushForResult<T>`.

**Notes:**

- The `Future<bool>` is the *success* indicator, not the result value —
  the result is the argument you pass to `pop`. To return data from a
  main-stack screen, open it with `pushForResult<T>(...)` and pop it with
  `pop(value)`; to return from a modal flow, use `run<T>` +
  `completeFlow`.
- `result` is typed `Object?`, recovered as `T?` at the
  `pushForResult<T>` await boundary (the same erase-then-recover model as
  `run<T>` / `completeFlow`).
- **`pop` runs through the guard pipeline like every other mutation.** A
  guard can prevent a pop (e.g. a form-dirty guard that asks "discard
  changes?"); `pop` then returns `false`. Always check the boolean if you
  care whether it happened.
- A guard can prevent a pop (e.g., a form-dirty guard that asks
  "discard changes?"). Always check the boolean if you care.

## back / historyGo

```dart
context.back();          // history-aligned single step back
context.historyGo(-2);   // two steps back; positive goes forward
```

Like `pop`, but aligned with **browser history** on the web. On the web `back()`
moves the browser history *pointer* (a true Back) and lets the inbound URL
restore the stack through your codec — so the screen you leave becomes a
*forward* entry instead of a lingering duplicate, and the browser's own
Back/Forward buttons keep mirroring the app stack across several steps.

**Use for:** A custom in-app back button on a web app where the browser
Back/Forward buttons should track multi-level back navigation.

**Notes:**

- **Falls back to `pop`** off the web, without a codec, or on a cold deep link
  (no app history behind the current entry) — safe to call everywhere.
- Unlike `pop`, it does **not** deliver a `pushForResult` value (the stack is
  restored from the URL). Keep `pop` when a screen must return a result.
- `historyGo(int delta)` is the multi-step form — negative back, positive
  forward; `back()` is `historyGo(-1)`.

## replaceTop

```dart
context.router<AppRoute>().replaceTop(const ProductDetail('sku-42'));
// Terse convenience (runtime-resolved):
context.replaceTop(const ProductDetail('sku-42'));
```

Removes the current top entry and pushes a new one in its place. The
stack length stays the same; back navigation goes to whatever was
underneath the removed entry, not to the replaced screen.

**Use for:** Onboarding steps (step 2 replaces step 1; back exits the
flow rather than returning to step 1), authentication redirects after
sign-in, dismissing-and-replacing a detail page.

**Distinguishing it from `push`:** After `push`, back returns to the
previous screen. After `replaceTop`, back returns to whatever was
already below. If you want the user to be able to go back to the
*current* screen, use `push`.

## pushOrReplaceTop

```dart
context.router<AppRoute>().pushOrReplaceTop(ProductDetail(productId));
// Terse convenience (runtime-resolved):
context.pushOrReplaceTop(ProductDetail(productId));
```

If the current top is the same runtime type as the proposed route,
replace it. Otherwise push.

**Use for:** Adaptive master-detail (a list with a swappable detail
pane), tab-style screens where selecting a different item should
update the current view rather than stack a new copy.

**The bug this prevents:** Without it, every tap on a different list
item pushes another detail entry. After ten selections, the stack
holds eleven entries (list + ten details), and pop has to fire ten
times to return to the list. With `pushOrReplaceTop`, the stack stays
two entries deep regardless of how many times the user switches
items.

**Notes:**

- "Same type" means runtime type equality, not value equality. So
  `pushOrReplaceTop(ProductDetail('a'))` on top of `ProductDetail('b')`
  replaces (because both are `ProductDetail`). If the runtime types
  differ, it pushes.
- Pair with adaptive page builders — see [ADAPTIVE.md](./ADAPTIVE.md).

## set

```dart
context.router<AppRoute>().set(const [Home(), ProductList()]);
// Terse convenience (runtime-resolved):
context.set(const [Home(), ProductList()]);
```

Replaces the entire stack with the provided list. Equivalent to
clearing and re-pushing, but in one mutation through the guard pipeline.

**Use for:**

- **Auth transitions.** Logging in: `set([const ShellHost()])`.
  Logging out: `set([const Login()])`. The whole previous stack goes
  away in one atomic operation.
- **Deep-link landing.** When a URL like `/products/sku-42` lands,
  the codec produces a stack `[Home(), ProductList(), ProductDetail('sku-42')]`
  and the router `set`s that whole stack at once. The user lands at
  the detail with a coherent back history.
- **Programmatic restore.** Loading a saved navigation state from disk.

**Distinguishing it from a sequence of `push` calls:** `set` is one
guard-pipeline pass; three sequential `push`es are three. If your guards
care about transitions, `set` is the right primitive for atomic state
changes.

### Declarative, state-driven stacks

`set` is also kaisel's answer to **declarative routing** — what
`AutoRouter.declarative` or a state-derived routes list does in other
routers. Those APIs rebuild the route list from ambient state on every
widget rebuild and diff the result. kaisel inverts that: the stack *is*
state, so derive it with a pure function and `set` it when your state
changes:

```dart
List<AppRoute> stackFor(AppModel m) => [
  const Home(),
  for (final doc in m.openDocuments) DocumentRoute(doc.id),
  if (m.showOnboarding) const Onboarding(),
];

model.addListener(() => router.set(stackFor(model)));
```

The result is the same minimal-change navigation — pages are keyed by
route value, so routes present in both old and new stacks keep their
page state — but derivation happens on state *events*, not widget
builds, and every derived stack still flows through the guard pipeline.
`stackFor` is a pure function you can unit test without a widget tree.

## run

```dart
final cardId = await context.router<AppRoute>().run<CardId>(
  const AddCardFlow(),
);
// Terse convenience (runtime-resolved):
final cardId = await context.run<CardId>(const AddCardFlow());
if (cardId != null) {
  // Flow completed with a result.
} else {
  // Flow was dismissed.
}
```

Opens a typed modal flow on top of the main stack. The flow has its
own sub-stack and its own router (accessible via `context.router<R>()`
from inside the flow's screens). The flow completes by calling
`context.completeFlow<T>(value)` or `context.dismissFlow()` — the
`Future` returned by `run` carries the completion value (or `null` on
dismiss).

**Use for:** Payment flows, multi-step pickers, "add a card" wizards,
confirmation dialogs that need to return a result, anywhere a
sub-flow has a clean entry, multi-step middle, and typed exit.

**Notes:**

- The flow's defining route must implement `KaiselModalRoute<T>`.
  Without it, `run<T>` throws.
- Flows are LIFO. A flow opened inside another flow nests on top; both
  flows' UIs stay mounted (the outer flow's state is preserved while
  the inner one is open).
- See [MODAL_FLOWS.md](./MODAL_FLOWS.md) for the full pattern.

## Decision aid

A short decision tree for picking the right method. Reach for the typed
`context.router<R>().<verb>` by default; drop to the terse `context.<verb>`
when the brevity clearly earns the runtime family check:

- **Going forward to a new screen?** `push`
- **Going forward to a screen that hands a value back?** `pushForResult<T>`
- **Going back (optionally returning a value)?** `pop` / `pop(result)`
- **Going back so the browser Back/Forward track it (web)?** `back()` /
  `historyGo(delta)`
- **Swapping the current screen in place (no back to current)?** `replaceTop`
- **Same screen type would land on top either way?** `pushOrReplaceTop`
- **Entire stack changes (auth, deep-link land)?** `set`
- **Opening a multi-step modal sub-flow that returns a result?** `run<T>`

## Common mistakes

| Mistake | Fix |
|:--------|:----|
| Using `push` everywhere | Many "navigate forward" calls are actually `replaceTop` (onboarding steps), `pushOrReplaceTop` (adaptive master-detail), or `run<T>` (modal flows). |
| Awaiting `push` expecting a result | `push` returns `Future<void>`. A main-stack screen that returns a value should be opened with `pushForResult<T>(...)` and popped with `pop(value)`; a modal flow uses `run<T>` + `completeFlow`. |
| Forgetting to handle the `null` result from `pushForResult<T>` / `run<T>` | `null` means dismissed without a value. Treat it as a first-class outcome, not an edge case. |
| Reaching for `run<T>` just to return a value from one screen | If it's a single screen on the main stack, `pushForResult<T>` is lighter and keeps the screen observable with root dialogs above it. Use `run<T>` when you genuinely need a multi-step flow in its own sub-router. |
| Pop loops to clear deep-link state | Use `set` to atomically replace the stack instead of popping repeatedly. |
| Pop'ing past the root | `pop` returns `false` when the stack is at one entry. It doesn't throw. Use the return value if you need to know. |
| Passing a wrong-family route to a terse `context.*` verb | The terse verbs resolve by *accepted argument type* at runtime, so a route from the wrong family throws at runtime. Use `context.router<R>().<verb>` to turn that into a compile error. |
