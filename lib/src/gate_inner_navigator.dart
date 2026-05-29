import 'package:flutter/material.dart';

import 'gate_route.dart';
import 'gate_router.dart';
import 'gate_router_delegate.dart';

/// A [Navigator] driven by a [GateRouter].
///
/// This is the "Navigator + state-sync" pattern that the main
/// `GateRouterDelegate` uses internally, factored out so it can be
/// embedded inside a shell branch or a modal flow. Wraps a [Navigator]
/// whose `pages` come from the router's stack and whose
/// `onDidRemovePage` syncs popped routes back into router state.
///
/// You usually don't construct this directly — `GateShell` and the
/// modal-flow rendering inside `GateRouterDelegate` use it for you.
/// It's exposed because if you're building your own router-aware
/// composite widget, this is the right primitive to embed.
class GateInnerNavigator<R extends GateRoute> extends StatefulWidget {
  /// Create a navigator bound to [router].
  const GateInnerNavigator({
    super.key,
    required this.router,
    required this.navigatorKey,
    required this.pageBuilder,
    this.pageWrapper,
    this.observers = const [],
  });

  /// The router whose stack drives the inner navigator's pages.
  final GateRouter<R> router;

  /// Key for the [Navigator] widget. Pass a stable key (e.g. one
  /// created in your parent's `initState`) so navigator state is
  /// preserved across rebuilds.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Resolves a route to a widget. Use pattern matching for
  /// exhaustiveness checking against your sealed route type.
  final GatePageBuilder<R> pageBuilder;

  /// Optional override of how each route is wrapped as a [Page].
  /// Defaults to [MaterialPage].
  final GatePageWrapper<R>? pageWrapper;

  /// Optional list of [NavigatorObserver]s for the inner navigator.
  final List<NavigatorObserver> observers;

  @override
  State<GateInnerNavigator<R>> createState() =>
      _GateInnerNavigatorState<R>();
}

class _GateInnerNavigatorState<R extends GateRoute>
    extends State<GateInnerNavigator<R>> {
  @override
  void initState() {
    super.initState();
    widget.router.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(GateInnerNavigator<R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.router, widget.router)) {
      oldWidget.router.removeListener(_onChange);
      widget.router.addListener(_onChange);
    }
  }

  @override
  void dispose() {
    widget.router.removeListener(_onChange);
    super.dispose();
  }

  Page<Object?> _wrap(BuildContext context, R route, LocalKey key) {
    final wrapper = widget.pageWrapper;
    final child = Builder(
      builder: (innerContext) => widget.pageBuilder(innerContext, route),
    );
    if (wrapper != null) return wrapper(route, child, key);
    return MaterialPage<Object?>(key: key, child: child);
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: widget.navigatorKey,
      observers: widget.observers,
      pages: [
        for (final entry in widget.router.entries)
          _wrap(context, entry.route, ValueKey<int>(entry.id)),
      ],
      onDidRemovePage: (page) {
        final key = page.key;
        if (key is ValueKey<int>) {
          widget.router.onPageRemoved(key.value);
        }
      },
    );
  }
}
