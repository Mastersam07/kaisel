import 'dart:async';

import 'package:flutter/foundation.dart';

import 'gate_guard.dart';
import 'gate_route.dart';

/// Non-generic view of a [GateRouter]'s navigation primitives.
///
/// Lets containers like `BranchedShellRouter` aggregate heterogeneously
/// typed routers (e.g. `GateRouter<HomeRoute>` and
/// `GateRouter<DiscoverRoute>`) under a single list without losing the
/// non-typed operations they need (can-pop and pop on the active branch
/// for back-button handling, plus type-erased stack capture/restore
/// for URL round-trips in v0.5+). The typed router still does what it
/// does; this is just the slice that's safe to call without knowing `R`.
abstract class GateNavigator implements Listenable {
  /// Whether [pop] would actually remove a route from this router.
  bool get canPop;

  /// Pop the top route from this router. Returns `false` if the
  /// router was already at root.
  Future<bool> pop();

  /// The router's current stack, type-erased to [GateRoute]. The
  /// typed `GateRouter<R>.stack` returns the same data as `List<R>`;
  /// this is the view shell containers see.
  List<GateRoute> get stack;

  /// Replace this router's stack from a (type-erased) list of routes.
  /// Throws [ArgumentError] if any element is not assignable to this
  /// router's underlying `R`. Used by [GateRouterDelegate] when
  /// restoring shell state from a URL.
  Future<void> restoreStack(List<GateRoute> stack);
}

/// Identity-stable wrapper for a route on the stack.
///
/// Two value-equal routes (e.g. `const Home()` pushed twice) still need
/// distinct identities for the [Navigator] to diff them correctly across
/// rebuilds. The router assigns a monotonic id per entry; the delegate
/// uses it to key the corresponding [Page]. Identity is preserved
/// across navigations where the route at a given position is unchanged,
/// so push/pop/replaceTop don't tear down sibling pages.
@immutable
@internal
class GateStackEntry<R extends GateRoute> {
  GateStackEntry(this.route) : id = _nextId++;

  /// The user-facing route.
  final R route;

  /// Identity-stable id used by the delegate to key the corresponding page.
  final int id;

  static int _nextId = 0;

  @override
  String toString() => 'GateStackEntry#$id($route)';
}

/// The navigation stack as observable state.
///
/// `GateRouter` is the single source of truth for navigation. The
/// `RouterDelegate` is a thin renderer over this object: it listens for
/// changes and builds a `Navigator` with the corresponding pages.
///
/// All mutations go through the methods on this class. Navigation is
/// list manipulation:
///
/// ```dart
/// await router.push(const ProductDetail('sku-42'));
/// await router.pop();
/// await router.replaceTop(const Home());
/// await router.set([const Home(), const Cart()]);
/// ```
///
/// As of v0.2, mutations return `Future<void>` because they pass through
/// the guard pipeline (which may be async). When no guards are
/// registered or all guards are synchronous, the future is already
/// complete on return and may be discarded — `router.push(x)` without
/// an `await` works fine.
///
/// Mutations are serialized: calling `push(a)` then `push(b)` without
/// awaiting still applies them in order. Each operation waits for the
/// previous one's guards to settle before running.
class GateRouter<R extends GateRoute> extends ChangeNotifier
    implements GateNavigator {
  /// Create a router with a single initial route and an optional guard
  /// pipeline.
  GateRouter({required R initial, List<GateGuard<R>> guards = const []})
    : _entries = [GateStackEntry<R>(initial)],
      _guards = List<GateGuard<R>>.unmodifiable(guards);

  /// Create a router from an existing stack. Must not be empty.
  factory GateRouter.fromStack(
    List<R> stack, {
    List<GateGuard<R>> guards = const [],
  }) {
    if (stack.isEmpty) {
      throw ArgumentError('Initial stack must contain at least one route.');
    }
    final router = GateRouter<R>._empty(guards: guards);
    for (final r in stack) {
      router._entries.add(GateStackEntry<R>(r));
    }
    return router;
  }

  GateRouter._empty({required List<GateGuard<R>> guards})
    : _entries = [],
      _guards = List<GateGuard<R>>.unmodifiable(guards);

  final List<GateStackEntry<R>> _entries;
  final List<GateGuard<R>> _guards;
  Future<void> _pending = Future<void>.value();

  // Modal flow state. Multiple flows can be active simultaneously
  // (nested modal flows). The list is a stack: flows are pushed by
  // [run] and popped by [completeFlow]/[dismissFlow] in LIFO order.
  final List<_ActiveFlow<R>> _flows = <_ActiveFlow<R>>[];

  /// The current stack as a read-only list of routes.
  @override
  List<R> get stack => List<R>.unmodifiable(_entries.map((e) => e.route));

  /// The route on top of the stack.
  R get current => _entries.last.route;

  /// Number of routes on the stack.
  int get depth => _entries.length;

  /// Whether a [pop] would actually remove a route.
  @override
  bool get canPop => _entries.length > 1;

  /// Whether at least one modal flow is currently active. Equivalent
  /// to `activeFlows.isNotEmpty`.
  bool get hasActiveFlow => _flows.isNotEmpty;

  /// All active modal flows, ordered from oldest (bottom of the
  /// modal stack) to newest (top, rendered on top of everything
  /// else). Empty when no flow is active. The last entry is the
  /// flow that [completeFlow] and [dismissFlow] will resolve.
  ///
  /// Hosts use this to render one modal layer per flow. Each entry
  /// exposes the flow's defining route and its sub-router. The
  /// completer is private to [run]/[completeFlow] so callers can't
  /// bypass the LIFO completion discipline.
  List<GateActiveFlow<R>> get activeFlows =>
      List<GateActiveFlow<R>>.unmodifiable(
        _flows.map((f) => GateActiveFlow<R>._(f.route, f.router)),
      );

  /// Internal view used by the delegate to key pages.
  @internal
  List<GateStackEntry<R>> get entries => List.unmodifiable(_entries);

  /// Push a route onto the top of the stack. Runs through guards.
  Future<void> push(R route) => _enqueue(() => _navigate([...stack, route]));

  /// Pop the top route. Returns `false` if the stack has only one route
  /// (we never pop to empty). Runs through guards.
  ///
  /// Concurrent pops applied rapidly each see the post-previous-pop
  /// stack, so two pops in a row from a 3-deep stack pop both routes
  /// rather than silently coalescing.
  @override
  Future<bool> pop() => _enqueue(() async {
    if (!canPop) return false;
    final next = stack.sublist(0, stack.length - 1);
    await _navigate(next);
    return true;
  });

  /// Replace the top route on the stack. Runs through guards.
  ///
  /// Only ever touches the top entry; the rest of the stack is
  /// untouched.
  Future<void> replaceTop(R route) => _enqueue(() {
    final next = [...stack];
    if (next.isEmpty) {
      next.add(route);
    } else {
      next[next.length - 1] = route;
    }
    return _navigate(next);
  });

  /// Push [route] onto the stack, or replace the top entry if [when]
  /// matches the current top route.
  ///
  /// The canonical case is master-detail at adaptive widths. Tapping
  /// a different item in the master should:
  ///
  /// - **push** the new detail if there's no detail on top yet
  ///   (`[List]` → `[List, Detail(id)]`),
  /// - **replace** the top entry if a detail is already there
  ///   (`[List, Detail(other)]` → `[List, Detail(id)]`).
  ///
  /// Replacing instead of pushing is what gives master-detail its
  /// in-place feel. If you always pushed, the stack would grow and
  /// the new top entry's previous neighbour would be another
  /// `Detail`, not `List`, so the adaptive absorbing arm wouldn't
  /// match and the Navigator would animate a slide-in.
  ///
  /// [when] defaults to "replace if the current top has the same
  /// runtime type as [route]". That works for the common sealed-
  /// route case where every detail variant shares one type. Pass
  /// an explicit predicate for finer control (or `(_) => false` to
  /// force a push, equivalent to calling [push] directly).
  Future<void> pushOrReplaceTop(R route, {bool Function(R current)? when}) {
    final predicate = when ?? ((c) => c.runtimeType == route.runtimeType);
    if (stack.isEmpty || !predicate(current)) {
      return push(route);
    }
    return replaceTop(route);
  }

  /// Replace the entire stack. Must not be empty. Runs through guards.
  ///
  /// [routes] is copied eagerly so subsequent caller mutation doesn't
  /// affect the queued navigation.
  Future<void> set(List<R> routes) {
    if (routes.isEmpty) {
      throw ArgumentError('Stack must contain at least one route.');
    }
    final captured = List<R>.of(routes);
    return _enqueue(() => _navigate(captured));
  }

  /// Pop routes until [predicate] returns true for the top route, or
  /// only one route remains on the stack. Runs through guards.
  Future<void> popUntil(bool Function(R route) predicate) => _enqueue(() {
    final next = [...stack];
    while (next.length > 1 && !predicate(next.last)) {
      next.removeLast();
    }
    return _navigate(next);
  });

  /// Used by the delegate to sync state when the navigator pops a page
  /// (e.g. system back). Synchronous: by the time the navigator notifies
  /// us, the page has already animated out, so we update state to match
  /// rather than trying to gate it.
  ///
  /// Guards do **not** run on this path. Pop-driven redirects should be
  /// implemented as listeners on app state (e.g. auth) that explicitly
  /// call [set] or [replaceTop], not as guards.
  @internal
  void onPageRemoved(int id) {
    final i = _entries.indexWhere((e) => e.id == id);
    if (i == -1) return; // already removed
    if (_entries.length == 1) return; // refuse to pop to empty
    _entries.removeAt(i);
    notifyListeners();
  }

  /// Called by the delegate on incoming deep links / route information.
  @internal
  Future<void> applyFromInformation(List<R> stack) =>
      _enqueue(() => _navigate(stack));

  /// Type-erased restore from a URL decode. Each element of [stack]
  /// must be assignable to `R`; if not, throws [ArgumentError] before
  /// touching state. Equivalent to [set] once the cast checks pass —
  /// guards still run.
  @override
  Future<void> restoreStack(List<GateRoute> stack) {
    final typed = <R>[];
    for (final r in stack) {
      if (r is! R) {
        throw ArgumentError(
          'restoreStack: route ${r.runtimeType} is not assignable to $R',
        );
      }
      typed.add(r);
    }
    return set(typed);
  }

  /// Present [flow] as a modal sub-flow and await its result.
  ///
  /// Creates an internal [GateRouter] for the flow's own stack. The
  /// flow's screens are rendered on top of the main stack by the
  /// delegate's `modalBuilder` (you must supply one — without it,
  /// flows have nowhere to be rendered).
  ///
  /// Resolves with the value passed to [completeFlow], or `null` if the
  /// flow is dismissed without an explicit completion (e.g. by tapping
  /// outside the modal, system back at the flow root, or [dismissFlow]).
  ///
  /// Nested flows are supported: calling [run] while another flow is
  /// active pushes a new flow on top, and flows complete in LIFO order
  /// (see [completeFlow]).
  ///
  /// Guards on the main router are **not** rerun when starting a flow
  /// (a flow is its own transient state, not a navigation on the main
  /// stack). The sub-router has no guards by default; pass [flowGuards]
  /// if you need them.
  Future<T?> run<T>(
    GateModalRoute<T> flow, {
    List<GateGuard<R>> flowGuards = const [],
  }) async {
    if (flow is! R) {
      throw ArgumentError(
        '${flow.runtimeType} must extend or implement $R to run as a flow.',
      );
    }
    final completer = Completer<Object?>();
    final flowRouter = GateRouter<R>(initial: flow as R, guards: flowGuards);
    flowRouter.addListener(notifyListeners);
    final entry = _ActiveFlow<R>(
      route: flow as GateModalRoute<Object?>,
      router: flowRouter,
      completer: completer,
    );
    _flows.add(entry);
    notifyListeners();

    try {
      final result = await completer.future;
      return result as T?;
    } finally {
      // If dispose() ran while we were awaiting, it has already
      // cleared the flow state (and the ChangeNotifier is now disposed,
      // so notifyListeners would throw). Only clean up and notify if
      // this entry is still tracked.
      if (_flows.remove(entry)) {
        flowRouter.removeListener(notifyListeners);
        flowRouter.dispose();
        notifyListeners();
      }
    }
  }

  /// Resolve the topmost active modal flow with [value]. No-op if no
  /// flow is active.
  ///
  /// The type parameter is for caller clarity. `completeFlow<bool>(true)`
  /// reads better than `completeFlow(true)`. The runtime check happens
  /// at the `await router.run<T>(...)` cast boundary.
  ///
  /// Nested flows resolve in LIFO order: only the topmost flow can be
  /// completed via this API. To unwind multiple flows, complete the
  /// topmost, await it, then complete the next.
  void completeFlow<T>(T? value) {
    if (_flows.isEmpty) return;
    final completer = _flows.last.completer;
    if (completer.isCompleted) return;
    completer.complete(value);
  }

  /// Dismiss the topmost active modal flow with `null`. No-op if no
  /// flow is active. Equivalent to `completeFlow<Null>(null)`.
  void dismissFlow() => completeFlow<Null>(null);

  @override
  void dispose() {
    // Resolve any in-flight flows so their awaiters don't hang.
    // Iterate over a copy so the finally blocks in `run` mutating
    // `_flows` doesn't disturb the loop.
    for (final flow in List<_ActiveFlow<R>>.from(_flows)) {
      if (!flow.completer.isCompleted) {
        flow.completer.complete(null);
      }
      flow.router.removeListener(notifyListeners);
      flow.router.dispose();
    }
    _flows.clear();
    super.dispose();
  }

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final next = _pending.then((_) => task());
    _pending = next.then(_void, onError: _void);
    return next;
  }

  static void _void(Object? _) {}

  Future<void> _navigate(List<R> proposed) async {
    final result = await _runGuards(stack, proposed);
    _applyStack(result);
  }

  Future<List<R>> _runGuards(List<R> current, List<R> proposed) async {
    var next = proposed;
    for (final guard in _guards) {
      next = await guard(current, next);
    }
    return next;
  }

  /// Apply [next] to the stack with identity preservation: entries
  /// whose route at the same position is equal keep their id. New
  /// positions get fresh entries. This means a push only allocates
  /// the new entry; existing pages keep their navigator state.
  void _applyStack(List<R> next) {
    if (next.isEmpty) {
      // Guards must not produce an empty stack. Refuse silently rather
      // than crashing — the user almost certainly wants the current
      // state preserved in this case.
      return;
    }
    if (_routesEqual(_entries, next)) return;

    final newEntries = <GateStackEntry<R>>[];
    for (var i = 0; i < next.length; i++) {
      if (i < _entries.length && _entries[i].route == next[i]) {
        newEntries.add(_entries[i]);
      } else {
        newEntries.add(GateStackEntry<R>(next[i]));
      }
    }

    _entries
      ..clear()
      ..addAll(newEntries);
    notifyListeners();
  }

  bool _routesEqual(List<GateStackEntry<R>> entries, List<R> next) {
    if (entries.length != next.length) return false;
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].route != next[i]) return false;
    }
    return true;
  }
}

/// Internal: state for one active modal flow. The router holds a
/// list of these as a LIFO stack. Each carries the defining route,
/// the sub-router driving its screens, and the completer that the
/// `await router.run<T>(...)` is waiting on.
class _ActiveFlow<R extends GateRoute> {
  _ActiveFlow({
    required this.route,
    required this.router,
    required this.completer,
  });

  final GateModalRoute<Object?> route;
  final GateRouter<R> router;
  final Completer<Object?> completer;
}

/// A read-only view of one entry in the active modal flow stack.
///
/// Exposed by [GateRouter.activeFlows] so hosts can render one modal
/// layer per active flow. The flow's defining route and its
/// sub-router are visible here; the completer is private to the
/// router so callers can't bypass the LIFO completion discipline.
@immutable
class GateActiveFlow<R extends GateRoute> {
  const GateActiveFlow._(this.route, this.router);

  /// The flow's defining route (the route passed to
  /// [GateRouter.run]). Type-erased to `GateModalRoute<Object?>`;
  /// the original `T` is recovered at the `await` boundary.
  final GateModalRoute<Object?> route;

  /// The sub-router driving the flow's screens.
  final GateRouter<R> router;
}
