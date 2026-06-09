# kaisel_devtools — design notes

kaisel has a natural advantage here that most routers don't, so design *toward*
that rather than copy a generic nav inspector.

## The one idea to build around

kaisel's whole thesis is **the navigation stack is typed value-state** (`List<R>`
of sealed, `props`-bearing routes). That means the extension isn't just a viewer
— the entire nav state is *serializable, diffable, and replayable data*. A
go_router/Navigator-1 inspector can't really do time-travel or stack diffs
cleanly; kaisel can, for free. So the differentiator is: **a navigation state
inspector with Redux-DevTools-style superpowers.**

Everything below is in service of that.

## What it should surface (the panels)

The delegate is the natural hub — it already holds the main router, the
registered nested hosts (branches/modules via `KaiselNestedHandle`), and
`activeFlows`. One snapshot from there covers most of it:

1. **Main stack** — the live `List<AppRoute>`, each entry showing: route type,
   its **`props` values** (e.g. `ChatDetail(chatId: 'a')` — readable because
   props are declared), and the **entry id** (the identity-stable id).
   Live-updates on every `notifyListeners`.
2. **Branched shells** — every branch's *own* typed stack side-by-side, which
   branch is active, per-tab depth. (See all tabs' back-stacks at once.)
3. **Module mounts** — each registered module, its mount prefix, its internal
   stack.
4. **Active modal flows** — the LIFO stack of flows: type, depth, and the
   pending awaiter's **result type** (`run<int>` → "awaiting `int?`"). Answers
   "why isn't my flow completing."
5. **Guard trace** — the most recent pipeline run: `input stack → guard₁(in,out)
   → guard₂(in,out) → … → final stack`. The single highest-value panel for the
   guards-as-pipeline model: "why did my navigation get rewritten?" — and the
   **one panel that requires a new core hook** (the router must retain its last
   pipeline run under `kDebugMode`); everything else is additive.
6. **Codec / URL** — live render of the URL the current `KaiselConfig` encodes
   to (round-trip through the codec), and the reverse.
7. **Adaptive view** — current breakpoint, and which router entries are
   **absorbed** into one rendered page (the rendered-pages ≠ router-stack
   distinction). Answers "why are two routes showing as one page?"
8. **Transitions log** — a chronological, filterable stream of mutations across
   all routers: the inferred operation (push / pop / replaceTop / set, or run /
   completeFlow), the target route, a timestamp, and which router. Answers "did
   my navigation actually fire?" without scattering `print`s. This is the same
   data as the stack diff, kept as history with the operation labelled — and the
   operation can be **inferred from the snapshot delta** (push = +1 entry, pop =
   −1, replaceTop = same length / new top, set = whole stack), so it needs no
   core change beyond the snapshot stream (flow and guard events ride on the
   existing flow/guard surfaces).
9. **Problems** — a dedicated panel for live diagnostics, so warnings live in one
   place instead of being scattered across entries: codec round-trip failures (a
   route the codec can't encode/decode — *not URL-addressable*), no-op mutations
   (the missing-`props` symptom above), routes the page builder doesn't handle,
   and branch/family mismatches. (Borrowed from zenrouter's Problems tab, which
   runs config checks — duplicated / missing / unknown paths — and counts routes
   whose `toUri()` throws; same framing, kaisel-specific checks.)

That set alone = "Flutter Inspector, scoped to navigation." A solid, shippable
v1 (read-only).

## The features that make it kaisel, not generic

These are the ones unlocked by stack-as-state — treat them as the reason to
build it:

- **Time-travel.** Record a snapshot per navigation; scrub/step through history;
  "jump to" any past stack. Pure because the stack is a function of state.
- **Stack diff.** Between two snapshots, show entries added / removed / replaced
  and — critically — **which ids were preserved vs newly allocated**. This
  visualizes the identity-stable diff, which is invisible but load-bearing.
  - *This would have made a real bug obvious:* a `replaceTop` that "did nothing"
    (because the new route was `==` the current one — a route with fields but no
    `props` override) produces an **empty diff**. Seeing "0 changes" on a tap is
    the smoking gun.
- **Missing-`props` detection, at runtime.** Per entry, show the `props` list.
  The *structural* "has fields but empty `props`" check can't run at runtime —
  Flutter has no reflection (`dart:mirrors` is stripped in AOT/web), so the
  runtime can't enumerate a route's declared fields to compare against `props`.
  So the real signal is the **no-op mutation**: an issued `push` / `replaceTop`
  / `set` whose new top is `==` the current top produces an *empty diff* —
  surface that as a warning. It's reflection-free and is the exact smoking gun
  for the `ChatDetail`-with-no-`props` bug. (Mechanism + the `fieldsNoProps`
  flag's status: see Hard parts.)
- **Codec playground.** Type a stack → get the URL; paste a URL → get the
  decoded stack; show `null` decodes. Test deep links without leaving DevTools.

## Optional v2: read-write (drive the app)

Once read-only is solid, the same channel can accept commands (guard behind a
clear "this mutates your app" toggle). **Keep these zero-setup — the user
declares nothing; everything reuses data the system already holds:**

- **Re-push from history (primary).** The snapshot / transitions log already
  contains *real instances* of every route visited this session. Show them as
  clickable chips — one click re-navigates. No declaration, no construction, no
  typing: the instances already exist, DevTools just re-dispatches them. Covers
  the dominant "jump back to a state I just saw" case.
- **Time-travel.** Jump to any recorded past stack — the stacks are already
  captured.
- **Deep-link tester.** Type a URI → decode through the codec → `push` /
  `replace` / `set`. The codec is already wired, so this reaches any
  URL-addressable route with zero *setup* (per-use typing, not declaration work).
- Pop / `replaceTop` / `set`, switch the active branch, complete/dismiss an
  active flow with a chosen value.
- **Guard replay** — run the pipeline against a hypothetical proposed stack and
  preview the result, without navigating.

The hand-declared **quick-routes palette** (`debugRoutes => [...]`, zenrouter's
approach) stays **strictly optional** — a power-user shortcut to one-click
*un-visited* states, never required. The three zero-setup mechanisms above are
the path.

**The one hard limit (honest).** A route that is *both* un-visited *and* not
URL-addressable *and* parametered can't be constructed from DevTools without the
user supplying a value or declaring it — the reflection/construction wall. It's a
small gap: such a route is reachable by neither a URL nor normal use.

## Architecture (so prod pays nothing)

- **Runtime hook**, debug-only. A `KaiselInspector` that live delegates register
  with in `kDebugMode`; it aggregates routers + nested handles + flows. It emits
  snapshots via `developer.postEvent('kaisel:nav', json)` on change (low-latency
  push), and registers `developer.registerExtension('ext.kaisel.*', …)` for
  on-demand snapshots and (v2) the mutation commands. Everything behind
  `kDebugMode`, so release builds strip it — **zero production cost.**
- **Extension UI**: a Flutter web app under `packages/kaisel/extension/devtools/`
  (the `devtools_extensions` convention — ships inside the published package,
  declared in `extension/devtools/config.yaml`), connecting via the DevTools
  extension API + VM service, subscribing to the events.
- Guard traces come from the router (have it retain the last pipeline run in
  debug); codec preview from the parser/codec.

**Discovery — register the hub, not every router (decided).** kaisel creates
many routers (every branch, module, and flow sub-router, churning as flows open
and close). Self-registering each one gives a flat list with no *roles* — a
branch router doesn't know it's a branch; the shell does, and the delegate
already aggregates the structured tree (main + nested handles + active flows) for
URL state. So the **delegate** self-registers with `KaiselInspector` in debug and
emits the structured snapshot; individual routers are not hooked. (A stray router
created outside any delegate simply won't appear — an acceptable gap, and the
reason to prefer explicit hub registration over walking the widget tree for
`RouterScope`s, which is fragile and timing-dependent.) Apps with **multiple
delegates** (several `MaterialApp.router`, embedded mini-apps, a test harness)
each register and show up as separate entries in the snapshot's `roots[]` — the
schema already models this; registration is simply per-delegate.

**Packaging — zero integration (decided).** Because the hook needs only
`dart:developer`, it lives inside `kaisel` behind `kDebugMode` and the delegate
self-registers — there is **no `dev_dependency` to add and no `init()` to call**.
The extension UI ships in `kaisel/extension/devtools/`, so DevTools auto-loads it
for anyone already depending on `kaisel`. This beats the common "separate runtime
package + two-line init in `main.dart`" split: the hook is tiny and stable while
the UI churns, so the coupling cost is negligible and the user does nothing.

**Two surfaces, one snapshot (borrowed from zenrouter).** zenrouter's devtools
is *not* a DevTools-window extension — it's an **in-app overlay** (a `kDebugMode`
FAB + `Overlay` you opt into) that renders the nav state on-device. That covers a
case our extension can't: **mobile / physical-device QA with no DevTools session
attached.** The key realisation is that our `KaiselInspector` snapshot is
**renderer-agnostic** — the same JSON that feeds the DevTools extension can feed
an optional in-app `KaiselDebugOverlay` widget. So we get both surfaces from one
contract: the DevTools panel (rich: diff, time-travel, history, guard trace) and
a lightweight in-app overlay (on-device, no VM-service plumbing, needs no
DevTools). **Build the extension first, the overlay second**, for two reasons:
(1) the extension is genuinely zero-integration (DevTools auto-loads it, the hook
auto-registers), whereas the overlay *must* be mounted in the widget tree — one
wrapper widget, since kaisel's `RouterConfig`/delegate has no single layout-wrap
hook like zenrouter's `Coordinator.layoutBuilder` — so the overlay can't honour
"users do nothing"; and (2) the extension is the differentiated, marketable
surface (zenrouter already ships an overlay; our leapfrog is the stack-as-state
panel). The overlay is a follow-on that earns its keep only for the on-device /
no-DevTools-session QA case.

## The runtime hook + snapshot schema (sketch)

This is the contract between the running app and the extension. Two halves: a
debug-only registry the delegate registers with, and the JSON it publishes.

### `KaiselInspector` — the runtime hook

Uses only `dart:developer` + `kDebugMode`, so it needs no extra dependency and
compiles out of release builds. The delegate is the hub; it implements a small
`KaiselInspectable` and registers itself.

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart'; // kDebugMode, Listenable

/// What a delegate exposes to the inspector. The delegate already knows the
/// main router, the nested handles (branches/modules) registered with it, the
/// active flows, and the codec — so one snapshot from here covers most panels.
abstract interface class KaiselInspectable {
  /// A serialisable snapshot of this root's navigation state (see schema).
  Map<String, Object?> debugSnapshot();

  /// Fires whenever [debugSnapshot] would change (the main router, any
  /// branch/module, or the flow stack notifying).
  Listenable get debugRevision;
}

/// Debug-only registry. Aggregates live roots and publishes nav snapshots to
/// DevTools over the VM service. Entirely inert outside [kDebugMode].
class KaiselInspector {
  KaiselInspector._();
  static final KaiselInspector instance = KaiselInspector._();

  final _roots = <int, KaiselInspectable>{};
  int _nextId = 0;
  bool _wired = false;
  bool _scheduled = false;

  /// Called by a delegate in its constructor (guarded by kDebugMode). Returns a
  /// token; pass it to [deregister] in dispose. No-op in release.
  int register(KaiselInspectable root) {
    if (!kDebugMode) return -1;
    final id = _nextId++;
    _roots[id] = root;
    root.debugRevision.addListener(_schedulePublish);
    _ensureExtensions();
    _schedulePublish();
    return id;
  }

  void deregister(int token) {
    if (!kDebugMode) return;
    _roots.remove(token)?.debugRevision.removeListener(_schedulePublish);
    _schedulePublish();
  }

  // Coalesce bursts of notifications into one event per microtask.
  void _schedulePublish() {
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      developer.postEvent('kaisel:nav', _snapshot());
    });
  }

  void _ensureExtensions() {
    if (_wired) return;
    _wired = true;
    // Pull: DevTools asks for a full snapshot on connect / refresh.
    developer.registerExtension('ext.kaisel.snapshot', (method, params) async {
      return developer.ServiceExtensionResponse.result(jsonEncode(_snapshot()));
    });
    // v2 push-back: DevTools drives navigation — see "command contract" below.
    // developer.registerExtension('ext.kaisel.command', _handleCommand);
  }

  Map<String, Object?> _snapshot() => {
    'v': 1,
    'roots': [for (final r in _roots.values) r.debugSnapshot()],
  };
}
```

The delegate side just assembles the snapshot from state it already holds:

```dart
// Inside KaiselRouterDelegate, behind kDebugMode:
@override
Listenable get debugRevision => router; // branches/modules/flows notify through it

@override
Map<String, Object?> debugSnapshot() => {
  'id': 'root-$_debugId',
  'main': _stackJson(router),
  'branches': [for (final h in _shellHandles) _shellJson(h)],
  'modules':  [for (final h in _moduleHandles) _moduleJson(h)],
  'flows':    [for (var i = 0; i < router.activeFlows.length; i++)
                 _flowJson(i, router.activeFlows[i])],
  'guardTrace': router.debugLastGuardRun?.toJson(), // router must retain it in debug
  'url': _codec?.encodeOrNull(captureConfig()),
};

Map<String, Object?> _stackJson(KaiselNavigator r) => {
  'depth': r.stack.length,
  'canPop': r.canPop,
  'entries': [
    for (final e in r.debugEntries) // exposes id + route
      {
        'id': e.id,
        'type': '${e.route.runtimeType}',
        'props': [for (final p in e.route.props) '$p'], // stringified, not serialised
        'label': '${e.route}',
        'fieldsNoProps': _looksLikeMissingProps(e.route),
      },
  ],
};
```

### Snapshot JSON schema (the contract)

`postEvent('kaisel:nav', <root document>)` on change; `ext.kaisel.snapshot`
returns the same document. Everything is stringified — routes may hold
non-serialisable values (a `Cart`, a callback), so the snapshot never tries to
serialise the actual objects, only `toString()` them.

```jsonc
{
  "v": 1,                       // schema version — bump on breaking changes
  "roots": [                    // one per live delegate (usually exactly one)
    {
      "id": "root-0",
      "main":     <Stack>,      // the main router's stack
      "branches": [<Shell>],    // shells registered with this delegate (may be [])
      "modules":  [<Module>],   // module mounts registered (may be [])
      "flows":    [<Flow>],     // active modal flows, outermost first (may be [])
      "guardTrace": <GuardTrace> | null,  // most recent pipeline run, if retained
      "url": "string | null"    // URL the current config encodes to, or null (no codec)
    }
  ]
}

// <Stack> — a single router's stack
{
  "depth": 2,
  "canPop": true,
  "entries": [
    {
      "id": 7,                  // identity-stable entry id (preserved across equal routes)
      "type": "ChatDetail",     // route.runtimeType
      "props": ["a"],           // each declared prop, stringified
      "label": "ChatDetail(chatId: a)",   // route.toString()
      "fieldsNoProps": false    // OPTIONAL opt-in hint; not auto-computable (no reflection) — see Hard parts
    }
  ]
}

// <Shell>
{
  "kind": "branched" | "homogeneous",
  "type": "MessagesRoute",      // the branch family / shell router type
  "activeBranch": 1,
  "branchCount": 3,
  "branches": [
    { "index": 0, "routeType": "HomeRoute", "stack": <Stack> }
  ]
}

// <Module>
{
  "prefix": "/checkout",
  "routeType": "CheckoutRoute",
  "stack": <Stack>
}

// <Flow> — outermost flow first; the topmost (innermost) is last
{
  "depth": 0,                   // nesting depth (0 = outermost flow)
  "type": "AddCardFlow",        // the modal route's runtimeType
  "resultType": "string | null", // T from KaiselModalRoute<T> if recoverable (usually null — erased)
  "stack": <Stack>              // the flow's own sub-router stack
}

// <GuardTrace> — the last pipeline run
{
  "input": [<EntryLite>],       // proposed stack going in
  "steps": [
    {
      "guard": "#0",            // guards are usually anonymous closures → index (best-effort name)
      "in":  [<EntryLite>],
      "out": [<EntryLite>],
      "changed": true
    }
  ],
  "output": [<EntryLite>]       // final stack the pipeline produced
}

// <EntryLite> — a route inside a trace (no id/props needed)
{ "type": "Login", "label": "Login()" }
```

### Command contract (v2, `ext.kaisel.command`)

```jsonc
// request params:
{
  "root": "root-0",
  "target": "main" | "branch:1" | "flow:0",
  "op": "pop" | "set" | "switchBranch" | "completeFlow" | "applySnapshot" | "replayGuards",
  "arg": <op-specific>
}
// set-from-url:   { "target": "main", "op": "set", "arg": { "url": "/checkout/shipping" } }
// switchBranch:   { "op": "switchBranch", "arg": 2 }
// completeFlow:   { "target": "flow:0", "op": "completeFlow", "arg": <json primitive> }
```

### Known limitations to design around

- **No arbitrary `push` from DevTools.** Routes are typed Dart values; you can't
  construct `ChatDetail('x')` from JSON. The feasible commands sidestep this:
  `pop`, `switchBranch(i)`, `completeFlow(primitive)`, `set`-from-URL (decode via
  the codec), `applySnapshot` (replay a stack the app already produced), and
  `replayGuards`. Arbitrary push needs a route factory the app opts into.
- **Guard names.** Pipeline guards are usually anonymous closures with no
  recoverable name — the trace is index-based (`#0`, `#1`) plus the in/out
  stacks.
- **Flow result type.** `KaiselModalRoute<T>`'s `T` is erased at runtime, so
  `resultType` is best-effort and typically `null`.
- **Adaptive view is render-time.** Which entries are absorbed into one page
  isn't in the core snapshot (it's known at render, not in the router state); it
  comes later as a delegate-reported rendered-pages-vs-stack mapping.
- **`guardTrace` and `debugEntries`/`debugLastGuardRun` are new debug surfaces**
  the router/delegate must expose under `kDebugMode`.

## Hard parts (decide these early)

Operational concerns that are cheap to design in now and painful to retrofit:

- **Privacy / redaction (ship in v1).** Route `props` routinely carry sensitive
  values — user ids, tokens, a whole `Cart`. Two safeguards: the hook is
  debug-only by default (it compiles out of profile/release), and routes can opt
  fields out of the snapshot with a redaction marker so they render as
  `[REDACTED]`. Build this into the snapshot serialiser from day one, not after
  the first leak.
- **Reconnect buffering.** DevTools is usually opened *after* the bug already
  happened. The hook should keep a ring buffer of the last N transitions
  (configurable; default ≈100, since chatty apps churn faster) and replay it on
  connect, so a developer sees recent history, not just future events. Resync
  the full snapshot on every (re)connect.
- **Event coalescing + a "burst" badge.** A rapid programmatic sequence
  shouldn't flood the channel. Coalesce on the app side (the sketch already
  debounces per microtask; add a time cap, ≈50ms) and surface a "N transitions"
  badge in the UI when events arrive faster than a human reads them.
- **Serialization is one-way; mark it.** Stringifying for *display* always works.
  *Navigating to* an entry from DevTools only works for routes the codec
  round-trips. The UI must clearly mark each entry as URL-routable vs
  display-only, so "jump to this state" is offered only where it can work.
- **What needs a core hook vs what's additive.** The live stack, branches,
  modules, flows, the diff, and the transitions log (via delta inference) are
  purely additive — they read existing state. The **guard trace** is the
  exception: it needs the router to retain its last pipeline run under
  `kDebugMode` (`debugLastGuardRun`), plus `debugEntries` for stable ids. Don't
  claim "zero core changes" — the highest-value debugging panel needs one.
- **Detecting missing `props` at runtime — what's actually feasible.** There is
  no reflection in Flutter, so the runtime cannot enumerate a route's fields to
  prove "has fields but empty `props`." Two honest paths: (1) the **build-time**
  detector is the `require_route_props` lint, which already catches it for
  analyzed code; (2) the **runtime** detector is the *symptom*, not the
  structure — a **no-op mutation** warning when an issued `push`/`replaceTop`/
  `set` produces an empty diff (the new route was `==` the current top). Prefer
  that; it's reflection-free, catches third-party/dynamically-loaded routes the
  lint never saw, and is the literal smoking gun. The schema's `fieldsNoProps`
  stays an **optional opt-in** field (populated only if a route discloses its
  fields via a debug mixin) — not something the runtime computes on its own.
- **Schema versioning.** The `v` field is the runtime↔UI contract. Rule:
  additive changes keep the same major and the extension **ignores unknown
  fields**; a breaking change bumps `v`, and the extension **degrades gracefully**
  — renders what it understands plus a "your kaisel and DevTools-extension
  versions differ" notice — rather than crashing. Both sides advertise the
  version they speak, so a mismatch is a soft warning, not a hard failure.

## Non-goals (defer indefinitely unless users ask)

- **Per-route render profiling** — DevTools' own performance profiler already
  covers this; don't reimplement it scoped to routes.
- **Automatic per-route screenshot capture** — sounds nice, expensive to do
  well, rarely used.
- **Route coverage analytics** ("which routes were visited this session") — a
  product-analytics concern, not a routing-devtools one.

These read well in the abstract and go unused in practice. Build on real signal,
not speculation.

## My suggested first cut

Don't boil the ocean. **v1 = read-only, three panels: Main stack (with props +
ids), Guard trace, Codec/URL preview** — plus the **stack-diff highlight**
between consecutive snapshots. That trio covers the most common "why did
navigation do that?" questions and immediately surfaces the props-equality
footgun. Add branches/flows/modules panels next, then the read-write/time-travel
layer last.

One thing to land first: there's **no central router registry** today, so the
delegate's self-registration hook (see *Discovery* under Architecture) is what
everything hangs off — build that, plus the redaction-aware snapshot serialiser,
before any panel.
