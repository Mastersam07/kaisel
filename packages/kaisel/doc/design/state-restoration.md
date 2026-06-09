# State restoration — design

**Status:** spec / not started · **Roadmap track:** State restoration (`RestorationManager`) · **Owner:** TBD

Design notes for adding Flutter `RestorationManager`-based state restoration to kaisel, so an app that the OS process-kills (iOS background-kill, Android low-memory) and relaunches comes back where the user left off. Grounded in the current code; file:line references are to the state at time of writing.

---

## 0. Reframing: there are *two* restorations, not one

The roadmap lists three sub-tasks, but they serve **two distinct user-visible features** with different requirements. Conflating them is the main trap.

| | **A. Stack restoration** | **B. Within-page state** |
|---|---|---|
| What survives | *which routes* are on the stack | scroll offset, text fields, expansion state *inside* a page |
| Needs | a **serializer** for the stack (the codec) | `restorationScopeId` (navigator) + `restorationId` (page) + `RestorationMixin` in the page's widgets |
| Depends on | nothing | **A** — the page must be reconstructed before its inner state can restore |
| Roadmap part | (c) | (a) + (b) |

B is worthless without A (no page → nothing to restore inner state into). **Build order: A first, then B.**

## 1. The two hard constraints (everything else follows)

**Constraint 1 — you cannot restore a stack without serializing routes.** Routes are typed Dart values; Flutter restoration only persists primitives. The **codec is the only serializer kaisel has**. Therefore:
- **Codec apps** can restore the stack.
- **Non-codec apps cannot** — unless they supply a codec (even a URL-less one). We can make that ergonomic; we cannot conjure serialization for opaque values. State this plainly, never paper over it.

**Constraint 2 — a page's `restorationId` must be stable across process death, but `KaiselStackEntry.id` is `_nextId++`** (`kaisel_core/lib/src/kaisel_router.dart:57`), a process-local counter that resets to 0 on relaunch. So:
- `restorationId: 'kaisel-$entryId'` **cannot work** — the same route gets a different id after restore, and the saved bucket is never found.
- The id must derive from **route identity**, not the runtime entry id. See §4 Phase 3.

## 2. Current state (grounded)

- ✅ Codec apps already have the *serialization round-trip*: `restoreRouteInformation(config) → RouteInformation(uri: codec.encode(config))` and `parseRouteInformation` back (`kaisel/lib/src/kaisel_route_information_parser.dart:66-78`). Nested shell/module state rides along **iff the codec encodes it** (it's in `currentConfiguration.nestedState` → `codec.encode`).
- ✅ Guards re-run on restore: `restoreStack → set → _navigate → _runGuards` (`kaisel_core/lib/src/kaisel_router.dart:325-344, 446-451`); the doc comment says *"guards still run."*
- ✅ Nested restore is wired: `setNewRoutePath` matches a `KaiselNestedHandle` by `configType` and calls `restoreFromConfig`, queuing in `_pendingNested` for cold-start (`kaisel/lib/src/kaisel_router_delegate.dart:317-340`).
- ❌ **No `restorationScopeId`** on either Navigator (`kaisel_router_delegate.dart:386`, `kaisel_inner_navigator.dart:188`).
- ❌ **No `restorationId`** on any of the 4 `MaterialPage` sites (`kaisel_router_delegate.dart:524-544`, `kaisel_inner_navigator.dart:127-147`).
- ❌ **No `RestorationMixin`** anywhere → no bucket transport for non-URL apps.
- ❓ **Unverified:** whether setting `MaterialApp.restorationScopeId` on a codec app *already* gives process-death stack restoration via Flutter's `Router` restoration. It almost certainly does (the parser implements `restoreRouteInformation`). Proving this is Phase 1.

## 3. How Flutter restoration works (so the design is anchored)

- The app declares a `restorationScopeId` high in the tree (`MaterialApp.restorationScopeId`), which establishes a `RootRestorationScope` and — for `MaterialApp.router` — turns on the underlying `Router`'s restoration.
- The `Router` saves its `RouteInformation` (via `delegate.currentConfiguration` → `parser.restoreRouteInformation`) into a restoration bucket as primitives; on relaunch it reads them back and calls `parser.parseRouteInformation → delegate.setNewRoutePath`.
- Independently, widgets with `RestorationMixin` + a `restorationId`, under a navigator/scope that has a `restorationScopeId`, restore their own `RestorableProperty`s from their bucket.

So **stack restoration = the Router path; within-page state = the scope/id path.** kaisel already implements the Router path's serializer; it implements none of the scope/id path.

## 3a. Prior art — go_router, auto_route, zenrouter

| | **go_router** | **auto_route** | **zenrouter** | **kaisel** |
|---|---|---|---|---|
| Route is | a string **path** | a string **name/path** | an object w/ built-in `toUri` | a typed value, **no built-in string** |
| Serializer | free (the path) | free (name + `pathState`) | `RouteUnique.serialize()` → URI, or `RouteRestorable` + `RestorableConverter` (→ Map) | the **optional** codec |
| Page `restorationId` | `pageKey.value` (path) | **route name**, opt-in `RestorationIdBuilder` | route's `restorationId` | **must add** (Phase 3) |
| Nested scope id | threaded to every Navigator | **host route's restorationId** (auto) | wired internally | **must add** (Phase 2) |
| Stack persistence | `Router` → `RouteInformation` | `Router` → `RouteInformation` (+ `state`) | `RestorableValue<Map>` (`RestorationMixin`), *independent* of the URL | Phase 1 (Router) or Phase 4 (bucket) |
| `RestorationMixin`? | no | no | **yes** | Phase 4 only |

**Lessons that shape this design:**

- **Two of three mainstream routers (go_router + auto_route) use only the `Router`/`RouteInformation` path and never touch `RestorationMixin`.** This validates **Phase 1 as the proven, mainstream approach**; the `RestorableProperty` direct-persist (Phase 4) is the outlier (only zenrouter).
- **All three bake serialization into the route** (path / name / `toUri` / converter). kaisel's optional codec is the structural reason non-codec apps can't restore — Constraint 1 is confirmed, not an oversight.
- **`restorationId` always derives from route identity, never a runtime counter** (go_router's pageKey, auto_route's name, zenrouter's route id). This validates Phase 3 (`route.restorationId`, not `entry.id`).
- **A smarter default than "null" (informed by auto_route):** auto_route defaults `restorationId` to the route name + an opt-in builder, but that **collides for parameterized routes** (two `/product/:id` share one id → state bleed). kaisel can do auto_route's convenience *with* safety, reusing the new `routeName`:
  ```dart
  String? get restorationId => props.isEmpty ? routeName : null;
  ```
  Parameterless routes restore automatically (`routeName` is unique + build-stable, even under `--obfuscate` — the minified name is consistent within one binary); parameterized routes stay off until the author supplies a param-aware id. See Phase 3.
- **zenrouter's two-tier `RouteUnique` / `RouteRestorable` split** is a better Phase-4 shape than a single whole-config codec: a route can be made restorable via a converter to a `Map` *without* being URL-addressable — precisely the non-URL gap.
- **auto_route also carries `state` in its `RouteInformation`** (not just the URI), so non-URL bits ride along; kaisel's `restoreRouteInformation` currently sets only `uri` — a possible small enhancement.
- **Sync-restore is a real constraint** (see §7) — zenrouter *requires* synchronous URI parsing because restore runs before the first frame.

## 4. Phased design

### Phase 1 — Stack restoration for codec apps (mostly verify + document)
Flutter restores `RouteInformation` across process death when the app's `restorationScopeId` is set, and kaisel's parser already produces/consumes it.
- **Verify** end-to-end: integration test with a codec app + `MaterialApp.restorationScopeId`, `tester.restartAndRestore()`, assert the main stack *and* active branch return.
- **Document** the recipe and the **codec-must-encode-nested-state** caveat (nested restores only if `codec.encode` includes it).
- Optional convenience: a `restorationScopeId:` passthrough on `KaiselRouterConfig` so users don't hand-wire `MaterialApp`.
- **Cost:** ~0 lib code; one integration test + docs. Highest value-to-effort.

### Phase 2 — `restorationScopeId` on navigators (part a)
- Add `restorationScopeId` to `KaiselRouterDelegate` → main `Navigator`.
- Add it to `KaiselInnerNavigator` → branch/module/flow navigators, with a **stable, unique** id per navigator: `'kaisel-branch-$index'`, `'kaisel-module-$prefix'`. (Flows: not restored — see §5.)
- Establishes the *scope* under which Phase 3's page `restorationId`s operate. Mechanical; no stability hazard (branch index / module prefix are stable across restore).

### Phase 3 — `restorationId` on pages (part b) — the careful one
- Add **`String? get restorationId`** to `KaiselRoute`, with a default that combines auto_route's convenience and a null-default's safety:
  ```dart
  String? get restorationId => props.isEmpty ? routeName : null;
  ```
  Parameterless routes auto-restore (their `routeName` is a unique, build-stable id); parameterized routes are **off until the author overrides** with a param-aware id (`'product-$id'`). Null = no `restorationId` on the page = within-page restoration off, no state-bleed.
  - *Alternative considered:* default flat `null` (fully opt-in, like the conservative reading). Rejected as less ergonomic — the `props.isEmpty` form makes the safe case work for free while keeping the risky case explicit.
- In the 4 default `MaterialPage` builders: `restorationId: ctx.route.restorationId` (null is a no-op).
- Users opt in per route with a **stable, cross-run** string that encodes identity *and* params:
  ```dart
  final class ProductDetail extends AppRoute {
    const ProductDetail(this.id);
    final String id;
    @override
    String get restorationId => 'product-$id';   // stable across restore
  }
  ```
- **Why opt-in, not a derived default:** a default like `'$routeName-${props.join()}'` is a footgun — props can contain objects whose `toString()` embeds a non-deterministic `hashCode`, breaking cross-run stability *silently*. Opt-in puts stability where the type author can guarantee it. Custom `pageWrapper`s set it themselves via `ctx.route`.

### Phase 4 — `RestorationBucket` transport for non-URL apps (part c)
For apps that want process-death restoration **without** URLs/deep-links:
- `KaiselRouterDelegate` gains `RestorationMixin`; registers a `RestorableString` holding `codec.encode(currentConfiguration).toString()`.
- `restoreState`: decode the string → `setNewRoutePath`. `saveState`: re-encode on change.
- Wired to a **bucket**, not the `PlatformRouteInformationProvider` — restores but never touches the platform URL.
- **Still requires a serializer** (Constraint 1). The new thing vs Phase 1 is the *transport*: private bucket instead of platform URL. Narrower audience (URL-averse mobile apps); real but lower priority.
- **Serializer shape — borrow zenrouter's two-tier model** rather than forcing the whole-config codec. A route opts into restoration either by being URL-encodable (the existing codec) *or* by providing a per-route converter to a `Map` (zenrouter's `RouteRestorable` + `RestorableConverter`). The latter lets non-URL state restore without inventing a URL for it.
- **Sync-restore tension (the gnarly bit, see §7):** `RestorationMixin.restoreState` runs synchronously before the first frame. `codec.decode` is synchronous, but applying the stack goes through kaisel's **async** guard pipeline (`_enqueue`/`_navigate`). Two options: (i) apply the restored entries synchronously *without* guards, then re-validate on the next microtask; or (ii) accept a one-frame flicker as the async apply lands. Phase 1 sidesteps this entirely because Flutter's `Router` awaits `setNewRoutePath`. This is the main reason Phase 4 is harder than Phase 1, and why it's deferred.

## 5. Cross-cutting decisions

- **Guards on restore:** re-run them (existing behavior). An auth guard must re-validate — don't restore *into* a screen that's now forbidden because the session died with the process. Already true; document it.
- **Modal flows (`run<T>`):** **not restored.** A flow is a sub-router + a pending `Completer<T>` that can't be serialized, and it's already excluded from the config (`activeFlows` isn't in `currentConfiguration`). On restore the app returns to the stack *beneath* the flow — consistent with "flows don't ride the URL." Imperative sheets/dialogs likewise don't restore.
- **Nested (shells/modules):** already serialize via `KaiselShellConfig`/`KaiselModuleConfig` and restore via `restoreFromConfig`, so they ride Phase 1 for free *if the codec encodes them*. Inactive branches keep in-memory state only (not restored), matching today's URL semantics.
- **Adaptive keys:** `KaiselAdaptiveKey(stableId, popId)` (`kaisel/lib/src/kaisel_adaptive.dart`) is also entry-id-derived, so adaptive pages share the same Phase-3 stability issue — but `restorationId` comes from `route.restorationId`, independent of the page key, so no special handling is needed.

## 6. New public API surface (total)

1. `KaiselRoute.restorationId` → `String?` (default `null`). *(kaisel_core — additive, non-breaking)*
2. `restorationScopeId` on `KaiselRouterDelegate`, `KaiselInnerNavigator`, `KaiselRouterConfig`, and the shell/branch specs. *(kaisel — additive)*
3. Phase 4 only: a way to choose the bucket transport (e.g. `KaiselRouterConfig.restorable(codec:, restorationScopeId:)` without a platform provider).

## 7. Risks / edge cases to cover in tests

- Restore into a stack a guard now rejects (auth expired) → lands on the guard's redirect, not the saved screen.
- Two value-equal routes in one stack sharing a `restorationId` → state bleed (document; it's the author's id choice).
- Cold-start restore where a nested handle hasn't mounted yet → `_pendingNested` path.
- Web vs mobile divergence (the browser URL is its own restoration; don't double-restore).
- **Sync-restore vs async guards (Phase 4):** `restoreState` is synchronous and runs before first frame, but the guard pipeline is async. zenrouter avoids this by *requiring* synchronous parsing (`parseRouteFromUriSync`); kaisel must pick a strategy (sync apply without guards + re-validate, or accept a frame's flicker). Phase 1 is immune (the `Router` awaits the async delegate).
- `restartAndRestore()` round-trip for each: main stack, branch + branch stack, module stack, and (Phase 3) a page's scroll offset.

## 8. Open design questions (from the roadmap)

- **Opt-in vs opt-out** for Phase 4: explicit `restorable: true` on the delegate, or default-on when a `restorationScopeId` is provided?
- **Branch-bucket ordering:** should a branch-level bucket restore independently when the parent shell hasn't restored yet, or wait?
- Whether to surface a single `restorationScopeId` that fans out to inner navigators automatically vs per-navigator control.

## 9. Suggested cut

**Phase 1 + 2 ship together** (small; unlock "codec app survives background-kill" + the scope for inner state — the 80/20). **Phase 3** next (the `restorationId` getter — the genuinely useful within-page piece). **Phase 4** only if a URL-averse-restoration user actually appears.

**Recommended first step:** Phase 1 — the verification test + docs — because it tells us how much already works before committing any new API.
