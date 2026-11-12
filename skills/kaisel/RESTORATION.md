# State restoration

Android and iOS kill backgrounded apps to reclaim memory. When the user
comes back, the app starts from scratch unless it restores itself, and
the user lands on the first screen instead of where they left off.
Restoration brings back two separate things:

- **The stack**: which screens were open.
- **Page state**: what was inside them, such as scroll offsets and text
  in fields.

Page state depends on the stack: a screen has to come back before its
contents can.

## Quick reference

| Goal | What to do |
|:-----|:-----------|
| Turn restoration on | `restorationScopeId` on `MaterialApp.router` |
| Restore the stack in an app with a codec | Nothing more; the codec saves and rebuilds it |
| Restore the stack in an app without a codec | `restoreRoute` on `KaiselRouterConfig` |
| Restore scroll and text inside pages | `restorationScopeId` on `KaiselRouterConfig`, a `restorationId` on parameterized routes, and `RestorationMixin` in your widgets |
| Restore a tab's own stack | A codec that writes `nestedState` (`KaiselShell` or `KaiselBranchedShell`) |

## 1. Turn it on

Restoration is off until the app has a restoration scope:

```dart
MaterialApp.router(routerConfig: _config, restorationScopeId: 'app');
```

Hold the `KaiselRouterConfig` as a top-level `final`, or create it once in
a `State`, so a relaunch builds it the same way.

## 2. The stack, with a codec

If your config has a `codec`, there is nothing else to do. Flutter's
`Router` saves the current URL and replays it on relaunch, and your codec
decodes it back into the stack. On mobile the URL is internal; the user
never sees it.

The codec decides what comes back. Anything it doesn't encode is lost,
including a shell's branch stack unless the codec writes `nestedState`
(see [CODEC.md](./CODEC.md) and section 5). A module's stack comes back
through its `ModuleStackCodec` when the app's codec is a
`ConfigCodecWithModules` (see [MODULES.md](./MODULES.md)); routes the URL
doesn't record, such as the screens under the module's mount, don't.

## 3. The stack, without a codec

Apps with no URLs can restore the **main** stack with `restoreRoute`.
kaisel saves each route's `routeName` and `props`; you rebuild the route
from them:

```dart
KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  restoreRoute: (name, props) => switch (name) {
    'ProductDetail' => ProductDetail(props[0] as String),
    'Settings' => const Settings(),
    _ => const Home(),
  },
  builder: ...,
);
```

- **`props` must be JSON-encodable** (strings, numbers, bools, null, lists
  and maps of those). If any route on the stack has other props, such as a
  `DateTime`, the stack isn't saved and the app restarts at `initial`. A
  debug log says so.
- **What you return is what goes on the stack.** If it doesn't match the
  saved name, a debug log warns you; that usually means a route your
  switch doesn't handle.
- **Under `--obfuscate`**, `routeName` defaults to the minified class name.
  Override it with a stable literal so the saved name matches your switch:

  ```dart
  final class ProductDetail extends AppRoute {
    const ProductDetail(this.id);
    final String id;

    @override
    String get routeName => 'ProductDetail';

    @override
    List<Object?> get props => [id];
  }
  ```

- **Only the main stack.** Shell branch stacks and module stacks need a
  codec.

## 4. State inside pages

Scroll offsets and text fields restore through Flutter's
`RestorationMixin`, which needs a scope on the navigator and an id on each
page.

```dart
KaiselRouterConfig<AppRoute>(
  restorationScopeId: 'main', // scopes the main navigator
  builder: ...,
);
```

Shell branches and module mounts get their own scope automatically. Each
page's id comes from `KaiselRoute.restorationId`:

- Routes **without** props default to their `routeName`, so they work as
  they are.
- Routes **with** props default to `null` and don't restore their page
  state, because every `ProductDetail` would otherwise share one bucket.
  Opt in with an id that includes the props:

  ```dart
  @override
  String get restorationId => 'product-$id';
  ```

Without the navigator's `restorationScopeId`, the stack can still come
back but the contents of its pages start fresh.

## 5. What doesn't restore

- **Modal flows.** An open `run<T>` flow is gone after a relaunch. The
  main stack under it comes back.
- **Pending results.** A screen opened with `pushForResult<T>` comes back,
  but the code that was awaiting it no longer exists, so its result goes
  nowhere. Keep anything that must survive in app state, not in a result.
- **Shell stacks, unless the codec writes them.** With a codec that writes
  `KaiselShellConfig` into `nestedState`, a `KaiselShell` or
  `KaiselBranchedShell` brings back its selected tab and that tab's
  stack.
- **Inactive tabs.** Only the selected tab's stack is saved. The others
  start at their first screen.
- **Nested state in apps without a codec.** `restoreRoute` saves the main
  stack only, so shells come back on their first tab and first screen, and
  modules on their first screen.
- **More than one level of nesting.** The saved URL holds one nested router.
  For a module inside a tab, or a shell inside a shell, only one level comes
  back; a `KaiselShell` nested in another router leaves the slot to the
  outer one.
- **Custom `KaiselInnerNavigator` containers.** Their stack starts over. Wrap
  one in `KaiselRestorationScope` to keep its pages' scroll and text state
  (see [SHELLS.md](./SHELLS.md)).

## Testing it

In widget tests, `tester.restartAndRestore()` simulates a relaunch with
the saved data. Create the config inside the app's `State` so the restart
rebuilds it:

```dart
await tester.pumpWidget(const MyApp());
await router.push(const ProductDetail('42'));
await tester.pumpAndSettle();

await tester.restartAndRestore();
await tester.pumpAndSettle();

expect(find.text('Product 42'), findsOneWidget);
```

On an Android device, turn on **Don't keep activities** in developer
options, background the app and reopen it.

## Common mistakes

| Mistake | Fix |
|:--------|:----|
| Setting `restorationScopeId` on `KaiselRouterConfig` but not on `MaterialApp.router` | The app-level scope turns restoration on; the config's only scopes the navigator. Set both. |
| Expecting a parameterized route's page state to restore | Override `restorationId` with a param-aware id like `'product-$id'`. |
| A `DateTime` or custom object in `props` with `restoreRoute` | Store a JSON-friendly form (an ISO string, an id) in `props`, or the whole stack isn't saved. |
| Relying on `runtimeType` names under `--obfuscate` | Override `routeName` with a stable literal. |
| Expecting an open flow or a pending result to survive | They don't. Reopen the flow from restored app state if it matters. |
| Expecting a tab's stack to come back without a codec | `restoreRoute` covers the main stack only. Use a codec that writes `nestedState`. |
