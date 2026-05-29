import 'dart:async';
import 'package:flutter/foundation.dart';

import 'gate_guard.dart';
import 'gate_route.dart';

/// Identity-stable wrapper for a route on the stack.
///
/// Two value-equal routes (e.g. `const Home()` pushed twice) still need
/// distinct identities for the [Navigator] to diff them correctly across
/// rebuilds. The router assigns a monotonic id per entry; the delegate
/// uses it to key the corresponding [Page]. Identity is preserved
/// across navigations where the route at a given position is unchanged,
/// so push/pop/replace don't tear down sibling pages.
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
/// await router.replace(const Home());
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
class GateRouter<R extends GateRoute> extends ChangeNotifier {
  /// Create a router with a single initial route and an optional guard
  /// pipeline.
  GateRouter({
    required R initial,
    List<GateGuard<R>> guards = const [],
  })  : _entries = [GateStackEntry<R>(initial)],
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

  // Modal flow state. At most one flow is active at a time in v0.3.
  GateRouter<R>? _flowRouter;
  GateModalRoute<Object?>? _flowRoute;
  Completer<Object?>? _flowCompleter;

  /// The current stack as a read-only list of routes.
  List<R> get stack => List<R>.unmodifiable(_entries.map((e) => e.route));

  /// The route on top of the stack.
  R get current => _entries.last.route;

  /// Number of routes on the stack.
  int get depth => _entries.length;

  /// Whether a [pop] would actually remove a route.
  bool get canPop => _entries.length > 1;

  /// Whether a modal flow is currently active.
  bool get hasActiveFlow => _flowRouter != null;

  /// The active modal flow's defining route, or null.
  GateModalRoute<Object?>? get activeFlowRoute => _flowRoute;

  /// The sub-router driving the active modal flow's screens, or null.
  GateRouter<R>? get activeFlowRouter => _flowRouter;

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
  Future<bool> pop() => _enqueue(() async {
        if (!canPop) return false;
        final next = stack.sublist(0, stack.length - 1);
        await _navigate(next);
        return true;
      });

  /// Replace the top route. Runs through guards.
  Future<void> replace(R route) => _enqueue(() {
        final next = [...stack];
        if (next.isEmpty) {
          next.add(route);
        } else {
          next[next.length - 1] = route;
        }
        return _navigate(next);
      });

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
  /// call [set] or [replace], not as guards.
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
  /// Throws [StateError] if a flow is already active — v0.3 does not
  /// support nested flows.
  ///
  /// Guards on the main router are **not** rerun when starting a flow
  /// (a flow is its own transient state, not a navigation on the main
  /// stack). The sub-router has no guards by default; pass [flowGuards]
  /// if you need them.
  Future<T?> run<T>(
    GateModalRoute<T> flow, {
    List<GateGuard<R>> flowGuards = const [],
  }) async {
    if (_flowRouter != null) {
      throw StateError(
        'A modal flow is already active. Complete it before starting another.',
      );
    }
    if (flow is! R) {
      throw ArgumentError(
        '${flow.runtimeType} must extend or implement $R to run as a flow.',
      );
    }
    final completer = Completer<Object?>();
    _flowCompleter = completer;
    _flowRoute = flow as GateModalRoute<Object?>;
    _flowRouter = GateRouter<R>(initial: flow as R, guards: flowGuards);
    _flowRouter!.addListener(notifyListeners);
    notifyListeners();

    try {
      final result = await completer.future;
      return result as T?;
    } finally {
      if (identical(_flowCompleter, completer)) {
        _flowRouter?.removeListener(notifyListeners);
        _flowRouter?.dispose();
        _flowRouter = null;
        _flowRoute = null;
        _flowCompleter = null;
        notifyListeners();
      }
    }
  }

  /// Resolve the active modal flow with [value]. No-op if no flow is
  /// active.
  ///
  /// The type parameter is for caller clarity — `completeFlow<bool>(true)`
  /// reads better than `completeFlow(true)` — but the runtime check
  /// happens at the `await router.run<T>(...)` cast boundary.
  void completeFlow<T>(T? value) {
    final completer = _flowCompleter;
    if (completer == null || completer.isCompleted) return;
    completer.complete(value);
  }

  /// Dismiss the active modal flow with `null`. No-op if no flow is
  /// active. Equivalent to `completeFlow<Null>(null)`.
  void dismissFlow() => completeFlow<Null>(null);

  @override
  void dispose() {
    // Resolve any in-flight flow so its awaiter doesn't hang.
    final completer = _flowCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }
    _flowRouter?.removeListener(notifyListeners);
    _flowRouter?.dispose();
    _flowRouter = null;
    _flowRoute = null;
    _flowCompleter = null;
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
