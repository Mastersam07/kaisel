import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kaisel_core/kaisel_core.dart';

/// Signature for [KaiselRouterDelegate.onScreenChanged]: called with the route
/// the user is now looking at, once per change, wherever in the app it lives.
typedef KaiselScreenCallback = void Function(KaiselRoute route);

/// Collapses the per-navigator route events of a whole app into one
/// "the visible screen changed" signal.
///
/// A shell app has one [Navigator] per branch plus the main stack, so an
/// observer registered per navigator holds per-branch state — switching
/// A → B → A re-reports A to the instance that never saw B. This reporter is
/// app-level, so its de-duplication spans every navigator.
///
/// Reports are coalesced with a microtask, which drains once the current frame
/// (or notification batch) finishes. Nested navigators mount and report after
/// their host, so the innermost screen wins and the route hosting a shell is
/// never reported as a screen of its own.
class KaiselScreenReporter {
  /// Create a reporter that forwards changes to [onScreenChanged].
  KaiselScreenReporter(this.onScreenChanged);

  /// The app's callback.
  final KaiselScreenCallback onScreenChanged;

  KaiselRoute? _reported;
  KaiselRoute? _pending;
  bool _scheduled = false;

  /// Record [route] as the currently visible one. Non-kaisel routes (dialogs,
  /// sheets, and anything else pushed imperatively) are ignored.
  void report(Route<dynamic>? route) {
    if (route?.settings.arguments case final KaiselRoute route) {
      reportRoute(route);
    }
  }

  /// Record [route] as the currently visible one. Used by shells, which know
  /// which branch is on screen when several are mounted.
  void reportRoute(KaiselRoute? route) {
    if (route == null) return;
    _pending = route;
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(_flush);
  }

  void _flush() {
    _scheduled = false;
    final next = _pending;
    _pending = null;
    if (next == null || next == _reported) return;
    _reported = next;
    onScreenChanged(next);
  }
}

/// The observer kaisel attaches to every navigator it builds, feeding one
/// shared [KaiselScreenReporter].
class KaiselScreenObserver extends NavigatorObserver {
  /// Create an observer reporting to [reporter].
  KaiselScreenObserver(this.reporter);

  /// The app-level sink this observer feeds.
  final KaiselScreenReporter reporter;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      reporter.report(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      reporter.report(previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      reporter.report(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      reporter.report(newRoute);
}
