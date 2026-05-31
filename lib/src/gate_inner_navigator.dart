import 'package:flutter/material.dart';

import 'gate_adaptive.dart';
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
/// You usually don't construct this directly. `GateShell`,
/// `GateBranch`, `GateModuleMount`, and the modal-flow rendering
/// inside `GateRouterDelegate` use it for you. It's exposed because
/// if you're building your own router-aware composite widget, this
/// is the right primitive to embed.
///
/// Adaptive (v0.9): pass [adaptivePageBuilder] instead of
/// [pageBuilder] to enable the adaptive pipeline inside this inner
/// navigator. Exactly one of the two must be provided.
class GateInnerNavigator<R extends GateRoute> extends StatefulWidget {
  /// Create a navigator bound to [router]. Provide exactly one of
  /// [pageBuilder] (simple) or [adaptivePageBuilder] (stack-aware).
  const GateInnerNavigator({
    super.key,
    required this.router,
    required this.navigatorKey,
    this.pageBuilder,
    this.adaptivePageBuilder,
    this.pageWrapper,
    this.observers = const [],
  }) : assert(
          (pageBuilder == null) != (adaptivePageBuilder == null),
          'Provide exactly one of pageBuilder or adaptivePageBuilder',
        );

  /// The router whose stack drives the inner navigator's pages.
  final GateRouter<R> router;

  /// Key for the [Navigator] widget. Pass a stable key (e.g. one
  /// created in your parent's `initState`) so navigator state is
  /// preserved across rebuilds.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Simple page builder. Resolves a route to a widget. Use pattern
  /// matching for exhaustiveness checking against your sealed route
  /// type. Null when [adaptivePageBuilder] is used.
  final GatePageBuilder<R>? pageBuilder;

  /// Adaptive page builder. Receives a stack context so the builder
  /// can return [GateAbsorbingPage] to collapse entries below it
  /// into one rendered page (master-detail at wide breakpoints).
  /// Null when [pageBuilder] is used.
  ///
  /// New in v0.9.
  final GateAdaptivePageBuilder<R>? adaptivePageBuilder;

  /// Optional override of how each route is wrapped as a [Page].
  /// Defaults to [MaterialPage].
  final GatePageWrapper<R>? pageWrapper;

  /// Optional list of [NavigatorObserver]s for the inner navigator.
  final List<NavigatorObserver> observers;

  @override
  State<GateInnerNavigator<R>> createState() => _GateInnerNavigatorState<R>();
}

class _GateInnerNavigatorState<R extends GateRoute>
    extends State<GateInnerNavigator<R>> {
  final HeroController _heroController = HeroController();

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

  Page<Object?> _wrapSimple(BuildContext context, R route, LocalKey key) {
    final wrapper = widget.pageWrapper;
    final child = Builder(
      builder: (innerContext) => widget.pageBuilder!(innerContext, route),
    );
    if (wrapper case final wrapper?) return wrapper(route, child, key);
    return MaterialPage<Object?>(key: key, child: child);
  }

  Page<Object?> _wrapAdaptive(R route, LocalKey key, Widget widget0) {
    final wrapper = widget.pageWrapper;
    if (wrapper case final wrapper?) return wrapper(route, widget0, key);
    return MaterialPage<Object?>(key: key, child: widget0);
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.router.entries;
    final pages = widget.adaptivePageBuilder != null
        ? buildAdaptivePages<R>(
            context: context,
            entries: entries,
            builder: widget.adaptivePageBuilder!,
            wrap: _wrapAdaptive,
          )
        : [
            for (final entry in entries)
              _wrapSimple(context, entry.route, ValueKey<int>(entry.id)),
          ];

    return HeroControllerScope(
      controller: _heroController,
      child: Navigator(
        key: widget.navigatorKey,
        observers: widget.observers,
        pages: pages,
        onDidRemovePage: (page) {
          final entryId = adaptiveEntryIdFromPageKey(page.key);
          if (entryId case final entryId?) {
            widget.router.onPageRemoved(entryId);
          }
        },
      ),
    );
  }
}
