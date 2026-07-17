# Modal flows

You need a multi-step experience — a checkout, a wizard, a picker —
that opens above the app, runs its own steps, and hands back a typed
result when it finishes.

Reference for `router.run<T>(...)`, `KaiselModalRoute<T>`, and
`KaiselModalBuilder`. Use modal flows when a sub-experience has a
clean entry, a multi-step middle, and a typed exit value. Payment
flows, add-card wizards, image pickers, confirmation dialogs that
return a result, OAuth-style consent screens — anywhere "open this,
do some stuff, return a value (or `null` if dismissed)" describes the
interaction.

## Flow or `pushForResult`?

If you only need **one screen on the main stack to hand a value back**,
you probably don't want a flow — use
[`pushForResult<T>`](./NAVIGATION.md):

```dart
final picked = await context.pushForResult<String>(const ColorPicker());
// inside ColorPicker: context.pop('teal');
```

Both return `Future<T?>`. The difference is *where the screen lives*:

- **`pushForResult<T>`** — the screen is a **normal route on the main
  stack**. A shared `RouteObserver` sees it, a root-navigator dialog
  renders above it, and back works normally. Lighter; no `modalBuilder`.
- **`run<T>`** — the flow runs in its **own sub-router**, rendered as an
  overlay by `modalBuilder`. Reach for it when you genuinely need a
  multi-step sub-stack, nesting, or a distinct modal presentation — not
  merely to return a value.

A good rule: single screen returning a value → `pushForResult`;
multi-step sub-experience → `run<T>`.

## The model

A modal flow is a sub-router that the main router runs on top of
itself. The flow has:

- A **defining route** (a `KaiselModalRoute<T>` subclass) that
  identifies the flow and carries any input parameters.
- A **typed completion contract** — the flow returns `T?` to whoever
  called `run<T>`. `T` is the success value; `null` means dismissal.
- An **internal sub-stack** — flow screens can push, pop, and navigate
  within the flow without affecting the main stack underneath.
- A **modal builder** that describes how the flow's UI overlays the
  main stack (bottom sheet, full-screen dialog, side drawer — the
  library is unopinionated about presentation).

## Quick reference

| Type | Purpose |
|:-----|:--------|
| `KaiselModalRoute<T>` | Abstract base for routes used as flow entry points. `T` is the typed completion value. |
| `KaiselRouter.run<T>(flow)` | Opens the flow. Returns `Future<T?>` that completes when the flow completes or dismisses. |
| `KaiselModalBuilder` | Function passed via `modalBuilder:` (on `KaiselRouterConfig` or `KaiselRouterDelegate`) — required when the app uses flows. |
| `KaiselActiveFlow<R>` | Represents one active flow at runtime (one per `run` call). The delegate iterates these to render flows on top of the main stack. |
| `context.completeFlow<T>(value)` | From inside a flow screen: complete the flow with `value`. |
| `context.dismissFlow()` | From inside a flow screen (or in response to a backdrop tap): dismiss with `null`. |

## The canonical pattern

### 1. Define the flow's entry route

```dart
final class AddCardFlow extends AppRoute
    implements KaiselModalRoute<CardId> {
  const AddCardFlow();
}
```

The route is a `KaiselRoute` (for the main router's stack) and a
`KaiselModalRoute<CardId>` (for the typed completion contract). Use
`implements` because a class can implement an interface; the abstract
`KaiselModalRoute<T>` is fine to implement as an interface even though
it's declared as a class.

For a flow with parameters:

```dart
final class PaymentFlow extends AppRoute
    implements KaiselModalRoute<bool> {
  const PaymentFlow({required this.amountCents});
  final int amountCents;
  @override
  List<Object?> get props => [amountCents];
}
```

### 2. Open the flow with `run<T>`

```dart
final cardId =
    await context.router<AppRoute>().run<CardId>(const AddCardFlow());
if (cardId != null) {
  // Flow completed with a card id.
} else {
  // Dismissed.
}
```

The typed `context.router<AppRoute>().run<CardId>(...)` is the idiomatic
form — it's compile-checked against the family. For brevity,
`context.run<CardId>(flow)` drops the type parameter and resolves the
nearest router that accepts the flow at runtime; the deliberate trade is
that a wrong-family flow throws at runtime instead of failing to compile.

The `Future<T?>` carries the result. `null` is the dismissal signal —
treat it as a real outcome, not an error.

### 3. Inside the flow, complete or dismiss

```dart
class _CardEntryScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(/* ... */ body: Column(children: [
      TextField(/* ... */),
      ElevatedButton(
        onPressed: () {
          final saved = const CardId('card_42');
          context.completeFlow<CardId>(saved);
        },
        child: const Text('Save'),
      ),
      TextButton(
        onPressed: () => context.dismissFlow(),
        child: const Text('Cancel'),
      ),
    ]));
  }
}
```

`completeFlow<T>` and `dismissFlow` are extension methods on
`BuildContext` provided by the kaisel scope. They resolve the nearest
enclosing active flow and complete it.

### 4. Wire up the `modalBuilder`

`modalBuilder:` is a `KaiselRouterConfig` parameter — declare the
config once at app lifetime and hand it to `MaterialApp.router`:

```dart
final _config = KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  builder: (context, route) => switch (route) {
    Home() => const HomeScreen(),
    AddCardFlow() => const _AddCardEntryScreen(),
    PaymentFlow(:final amountCents) =>
      _PaymentFlowScreen(amount: amountCents),
  },
  modalBuilder: (context, flow, child) {
    // `child` is the flow's rendered widget tree (running its own
    // sub-stack inside). Wrap it however the design calls for.
    return Stack(
      children: [
        GestureDetector(
          onTap: () => context.dismissFlow(),
          child: Container(color: Colors.black54),
        ),
        Center(
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 480,
              child: child,
            ),
          ),
        ),
      ],
    );
  },
);

// build: MaterialApp.router(routerConfig: _config, theme: ...)
```

The `modalBuilder` is required when `run<T>` is used anywhere in the
app. Without it, `run` throws. (The lower-tier explicit form —
`KaiselRouterDelegate(router:, builder:, modalBuilder:)` — still works
if you're managing the delegate by hand.)

`child` arrives already wrapped in a transparent `Material`, so flow
screens can use material widgets (`ListTile`, `TextField`, ...) without
a `Scaffold`, and the builder's own decoration can be a plain
`Container` — the framework's "No Material widget found" assert can't
fire inside a flow.

## Sub-stack inside a flow

A flow can push and pop within itself. From inside a flow screen,
`context.router<AppRoute>()` resolves to the *flow's* sub-router, not
the main one — so `.push(...)`, `.pop()`, and `.replaceTop(...)` mutate
the flow's stack, not the underlying main stack.

```dart
// Inside _CardEntryScreen, going to the next step in the flow:
context.router<AppRoute>().push(const _CardConfirmStep());

// Now the flow's sub-stack is [AddCardFlow, _CardConfirmStep].
// The main stack is untouched.
```

The flow's defining route (`AddCardFlow`) is the bottom of the flow's
sub-stack and is implicitly there — you don't push it yourself. Pushing
new routes adds to the flow's sub-stack on top of the defining route.

## Nested flows (LIFO)

A flow opened inside another flow nests on top. Both flows' UIs stay
mounted — the outer flow's state is preserved while the inner one is
open.

```dart
// In a PaymentFlow screen, open a sub-flow to add a card:
final newCardId = await context.run<CardId>(const AddCardFlow());
if (newCardId != null) {
  // The PaymentFlow's state is still here, including its cards list,
  // its selected amount, anything in StatefulWidget state. The
  // AddCardFlow ran on top, completed, and the result is back.
}
```

The delegate iterates `activeFlows` and calls `modalBuilder` for each,
so two flows nested means two overlay layers. The outer one renders
first (bottom of the modal stack); the inner renders on top.

## Per-flow state preservation

State inside a flow's screens (StatefulWidget state, controllers,
focus nodes) is preserved across opening and closing nested flows.
The outer flow doesn't get rebuilt when an inner flow opens — it just
gets covered by the inner overlay. When the inner closes, the outer
is still there, with its state intact.

This is the right default. A payment flow that loses its cart when
you open a card-entry sub-flow would be useless.

## Dismissal semantics

There are three ways a flow can end:

- **Complete.** Caller of `run<T>` receives the value. Use
  `context.completeFlow<T>(value)`.
- **Dismiss.** Caller receives `null`. Use `context.dismissFlow()`,
  tap the scrim, or rely on whatever dismissal gesture the
  `modalBuilder` exposes.
- **External teardown.** Disposing the router (`router.dispose()`)
  resolves every still-pending flow with `null`, so an awaiting
  `run<T>` never hangs. There's no per-flow cancel API: `dismissFlow()`
  resolves the *topmost* flow, so to force a flow shut from outside
  (e.g. logout while a flow is open) you tear down the host, or
  `dismissFlow()` from the top down.

All of these resolve the `Future<T?>`. The caller should always handle
`null` as a first-class outcome.

## Dialogs and observers over a flow

A flow is a **route on the main navigator**, so dialogs and observers
compose with it by Flutter's normal single-overlay rules:

- **Showing a dialog/loader over a flow.** `showDialog(...)` /
  `showModalBottomSheet(...)` render **above an active flow for both
  `useRootNavigator` values** — the flow is a route in the same navigator,
  so a later-pushed dialog stacks on top. The default
  (`useRootNavigator: true`) resolves the root navigator and covers the
  chrome; `false` targets the nearest navigator. A dialog shown from the
  `navigatorKey` context you attach to your config also lands on top.
- **The main navigator's observers see the flow boundary.** Because the
  flow is a route there, that navigator's observers receive its `didPush`
  / `didPop`, so a `RouteObserver` on the main stack reports when a flow
  opens and closes, and a `RouteAware` screen beneath the flow reacts to
  it. A flow's *internal* screens run on its own inner navigator, which
  gets its own observer instances (a `NavigatorObserver` belongs to one
  `Navigator`), so they are observed separately.
- **Customising a flow's entrance.** A `pageWrapper` can give a flow its
  own transition by branching on `KaiselPageWrapperContext.isFlow` and
  returning a (typically non-opaque) page; otherwise the flow appears
  instantly. Forward `name` / `arguments` from `ctx.route` on a custom
  flow page so it stays identifiable to observers.

## Common mistakes

| Mistake | Fix |
|:--------|:----|
| Pushing a `KaiselModalRoute<T>` via `push` instead of `run<T>` | Push "works" mechanically but loses the typed completion contract. There's no way to await the result. Always use `run<T>`. (A planned `avoid_modal_route_on_main_stack` lint would catch this; it's roadmapped, not yet implemented.) |
| Forgetting to register `modalBuilder` on the delegate when using `run<T>` | `run` throws. The library can't know how to overlay a flow without a builder. |
| Implementing `KaiselModalRoute<dynamic>` to "be flexible about return type" | Pick a concrete type. The callers of `run<T>` need to know what they're awaiting. `dynamic` defeats the type safety the library is designed for. |
| Treating `null` from `run<T>` as an error | `null` means the user dismissed. It's a normal outcome. The flow happened, the user chose not to commit; the calling code should handle this gracefully. |
| Calling `context.router<R>()` inside a flow expecting the main router | Inside a flow, `context.router<R>()` is the flow's sub-router. To navigate the main stack from inside a flow, you usually shouldn't — complete or dismiss the flow first, then the caller handles the main stack navigation. |
| Storing a reference to the flow's `KaiselRouter` outside the flow's lifetime | The flow's sub-router exists only while the flow is open. Holding a reference after the flow completes leaks a disposed `ChangeNotifier`. |
