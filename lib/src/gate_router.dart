import 'package:flutter/foundation.dart';

import 'gate_route.dart';

/// Identity-stable wrapper for a route on the stack.
///
/// Two value-equal routes (e.g. `const Home()` pushed twice) still need
/// distinct identities for the [Navigator] to diff them correctly across
/// rebuilds. The router assigns a monotonic id per entry; the delegate
/// uses it to key the corresponding [Page].
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
/// router.push(const ProductDetail('sku-42'));
/// router.pop();
/// router.replace(const Home());
/// router.set([const Home(), const Cart()]);
/// ```
class GateRouter<R extends GateRoute> extends ChangeNotifier {
  /// Create a router with a single initial route.
  GateRouter({required R initial})
      : _entries = [GateStackEntry<R>(initial)];

  /// Create a router from an existing stack. Must not be empty.
  factory GateRouter.fromStack(List<R> stack) {
    if (stack.isEmpty) {
      throw ArgumentError('Initial stack must contain at least one route.');
    }
    final router = GateRouter<R>._empty();
    for (final r in stack) {
      router._entries.add(GateStackEntry<R>(r));
    }
    return router;
  }

  GateRouter._empty() : _entries = [];

  final List<GateStackEntry<R>> _entries;

  /// The current stack as a read-only list of routes.
  List<R> get stack =>
      List<R>.unmodifiable(_entries.map((e) => e.route));

  /// The route on top of the stack.
  R get current => _entries.last.route;

  /// Number of routes on the stack.
  int get depth => _entries.length;

  /// Whether a [pop] would actually remove a route.
  bool get canPop => _entries.length > 1;

  /// Internal view used by the delegate to key pages.
  @internal
  List<GateStackEntry<R>> get entries => List.unmodifiable(_entries);

  /// Push a route onto the top of the stack.
  void push(R route) {
    _entries.add(GateStackEntry<R>(route));
    notifyListeners();
  }

  /// Pop the top route. Returns `false` if the stack has only one route
  /// (we never pop to empty).
  bool pop() {
    if (!canPop) return false;
    _entries.removeLast();
    notifyListeners();
    return true;
  }

  /// Replace the top route.
  void replace(R route) {
    if (_entries.isEmpty) {
      _entries.add(GateStackEntry<R>(route));
    } else {
      _entries[_entries.length - 1] = GateStackEntry<R>(route);
    }
    notifyListeners();
  }

  /// Replace the entire stack. Must not be empty.
  void set(List<R> routes) {
    if (routes.isEmpty) {
      throw ArgumentError('Stack must contain at least one route.');
    }
    _entries
      ..clear()
      ..addAll(routes.map(GateStackEntry<R>.new));
    notifyListeners();
  }

  /// Pop routes until [predicate] returns true for the top route, or
  /// only one route remains on the stack.
  void popUntil(bool Function(R route) predicate) {
    var changed = false;
    while (_entries.length > 1 && !predicate(_entries.last.route)) {
      _entries.removeLast();
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Remove the entry with the given internal id, if present.
  ///
  /// Used by the delegate to sync state with the navigator when the
  /// system back button pops a page. Returns `true` if a removal
  /// happened.
  @internal
  bool removeById(int id) {
    final i = _entries.indexWhere((e) => e.id == id);
    if (i == -1) return false;
    if (_entries.length == 1) return false; // never pop to empty
    _entries.removeAt(i);
    notifyListeners();
    return true;
  }
}
