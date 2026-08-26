import 'package:flutter/foundation.dart' show kDebugMode, listEquals;
import 'package:flutter/material.dart';
import 'package:kaisel_core/framework.dart';

import 'kaisel_adaptive.dart';
import 'kaisel_default_page.dart';
import 'kaisel_page_scope.dart';
import 'kaisel_page_wrapper.dart';
import 'kaisel_router_delegate.dart';
import 'kaisel_screen_signal.dart';

/// A [Navigator] driven by a [KaiselRouter].
///
/// This is the "Navigator + state-sync" pattern that the main
/// `KaiselRouterDelegate` uses internally, factored out so it can be
/// embedded inside a shell branch or a modal flow. Wraps a [Navigator]
/// whose `pages` come from the router's stack and whose
/// `onDidRemovePage` syncs popped routes back into router state.
///
/// You usually don't construct this directly. `KaiselShell`,
/// `KaiselBranch`, `KaiselModuleMount`, and the modal-flow rendering
/// inside `KaiselRouterDelegate` use it for you. It's exposed because
/// if you're building your own router-aware composite widget, this
/// is the right primitive to embed.
///
/// Adaptive: pass [adaptivePageBuilder] instead of
/// [pageBuilder] to enable the adaptive pipeline inside this inner
/// navigator. Exactly one of the two must be provided.
class KaiselInnerNavigator<R extends KaiselRoute> extends StatefulWidget {
  /// Create a navigator bound to [router]. Provide exactly one of
  /// [pageBuilder] (simple) or [adaptivePageBuilder] (stack-aware).
  const KaiselInnerNavigator({
    super.key,
    required this.router,
    required this.navigatorKey,
    this.pageBuilder,
    this.adaptivePageBuilder,
    this.pageWrapper,
    this.observers = const [],
    this.reportsScreen = true,
  }) : assert(
         (pageBuilder == null) != (adaptivePageBuilder == null),
         'Provide exactly one of pageBuilder or adaptivePageBuilder',
       );

  /// The router whose stack drives the inner navigator's pages.
  final KaiselRouter<R> router;

  /// Key for the [Navigator] widget. Pass a stable key (e.g. one
  /// created in your parent's `initState`) so navigator state is
  /// preserved across rebuilds.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Simple page builder. Resolves a route to a widget. Use pattern
  /// matching for exhaustiveness checking against your sealed route
  /// type. Null when [adaptivePageBuilder] is used.
  final KaiselPageBuilder<R>? pageBuilder;

  /// Adaptive page builder. Receives a stack context so the builder
  /// can return [KaiselAbsorbingPage] to collapse entries below it
  /// into one rendered page (master-detail at wide breakpoints).
  /// Null when [pageBuilder] is used.
  final KaiselAdaptivePageBuilder<R>? adaptivePageBuilder;

  /// Optional override of how each route is wrapped as a [Page].
  /// Defaults to [MaterialPage].
  final KaiselPageWrapper<R>? pageWrapper;

  /// Optional list of [NavigatorObserver]s for the inner navigator.
  final List<NavigatorObserver> observers;

  /// Whether this navigator feeds the app-level `onScreenChanged` signal.
  ///
  /// False for a shell's branch navigators: every branch mounts and pushes its
  /// root, but only one is on screen, so the shell reports the active branch's
  /// top instead.
  final bool reportsScreen;

  @override
  State<KaiselInnerNavigator<R>> createState() =>
      _KaiselInnerNavigatorState<R>();
}

class _KaiselInnerNavigatorState<R extends KaiselRoute>
    extends State<KaiselInnerNavigator<R>> {
  final HeroController _heroController = HeroController();

  // Observers from the app-wide [KaiselObserverScope], built fresh for this
  // navigator (a NavigatorObserver belongs to one Navigator), merged with any
  // per-instance [KaiselInnerNavigator.observers]. Cached so the list instance
  // is stable across rebuilds.
  KaiselObserversBuilder? _observersBuilder;
  KaiselScreenObserver? _screenObserver;
  List<NavigatorObserver> _scopeObservers = const <NavigatorObserver>[];
  List<NavigatorObserver> _observers = const <NavigatorObserver>[];

  @override
  void initState() {
    super.initState();
    widget.router.addListener(_onChange);
  }

  KaiselWebTransition _webTransition = KaiselWebTransition.fade;
  bool _androidPredictiveBack = false;
  final _absorbedChangeReporter = KaiselAbsorbedChangeReporter();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _webTransition = KaiselWebTransitionScope.of(context);
    _androidPredictiveBack = KaiselWebTransitionScope.androidPredictiveBackOf(
      context,
    );
    final reporter = widget.reportsScreen
        ? KaiselObserverScope.reporterOf(context)
        : null;
    if (!identical(reporter, _screenObserver?.reporter)) {
      _screenObserver = switch (reporter) {
        final reporter? => KaiselScreenObserver(reporter),
        _ => null,
      };
      _mergeObservers();
    }
    final builder = KaiselObserverScope.of(context);
    if (!identical(builder, _observersBuilder)) {
      _observersBuilder = builder;
      _scopeObservers = builder?.call() ?? const <NavigatorObserver>[];
      _mergeObservers();
    }
  }

  void _mergeObservers() {
    _observers = <NavigatorObserver>[
      ..._scopeObservers,
      ...widget.observers,
      ?_screenObserver,
    ];
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(KaiselInnerNavigator<R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.router, widget.router)) {
      oldWidget.router.removeListener(_onChange);
      widget.router.addListener(_onChange);
    }
    if (!listEquals(oldWidget.observers, widget.observers)) _mergeObservers();
  }

  @override
  void dispose() {
    widget.router.removeListener(_onChange);
    super.dispose();
  }

  Page<Object?> _wrapSimple(KaiselPageWrapperContext<R> ctx) {
    final wrapper = widget.pageWrapper;
    if (wrapper case final wrapper?) return wrapper(ctx);
    return kaiselDefaultPage(
      ctx,
      transition: _webTransition,
      androidPredictiveBack: _androidPredictiveBack,
    );
  }

  Page<Object?> _wrapAdaptive(KaiselPageWrapperContext<R> ctx) {
    final wrapper = widget.pageWrapper;
    if (wrapper case final wrapper?) return wrapper(ctx);
    return kaiselDefaultPage(
      ctx,
      transition: _webTransition,
      androidPredictiveBack: _androidPredictiveBack,
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.router.entries;
    final pages = switch (widget.adaptivePageBuilder) {
      final builder? => buildAdaptivePages<R>(
        context: context,
        entries: entries,
        builder: builder,
        wrap: _wrapAdaptive,
        reportAbsorption: kDebugMode
            ? widget.router.debugSetAbsorbedPositions
            : null,
        reportRenderedRoutes: (rendered) => _absorbedChangeReporter.report(
          stack: widget.router.stack,
          rendered: rendered,
          observers: _observers,
        ),
      ),
      _ => [
        for (var i = 0; i < entries.length; i++)
          _wrapSimple(
            KaiselPageWrapperContext<R>(
              route: entries[i].route,
              child: KaiselPageScope(
                route: entries[i].route,
                position: i,
                stackLength: entries.length,
                previous: i > 0 ? entries[i - 1].route : null,
                child: Builder(
                  builder: (innerContext) =>
                      widget.pageBuilder!(innerContext, entries[i].route),
                ),
              ),
              key: ValueKey<int>(entries[i].id),
              position: i,
              stackLength: entries.length,
              previous: i > 0 ? entries[i - 1].route : null,
            ),
          ),
      ],
    };

    return HeroControllerScope(
      controller: _heroController,
      child: Navigator(
        key: widget.navigatorKey,
        observers: _observers,
        restorationScopeId: KaiselRestorationScope.of(context),
        pages: pages,
        onDidRemovePage: (page) {
          final entryId = adaptiveEntryIdFromPageKey(page.key);
          if (entryId != null) {
            widget.router.onPageRemoved(entryId);
          }
        },
      ),
    );
  }
}

/// Carries the restoration scope id for the [KaiselInnerNavigator] below it.
///
/// Shells install one per branch (`kaisel-branch-<i>`) and modules one per
/// mount, so each nested navigator gets a stable, unique
/// [Navigator.restorationScopeId]. Absent (null) for the main stack and flows,
/// which don't restore through it.
class KaiselRestorationScope extends InheritedWidget {
  /// Create a scope carrying [restorationId] for the navigator below.
  const KaiselRestorationScope({
    super.key,
    required this.restorationId,
    required super.child,
  });

  /// The id handed to the nested navigator's [Navigator.restorationScopeId].
  final String? restorationId;

  /// The nearest scope's [restorationId], or null when there is none.
  static String? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<KaiselRestorationScope>()
      ?.restorationId;

  @override
  bool updateShouldNotify(KaiselRestorationScope oldWidget) =>
      oldWidget.restorationId != restorationId;
}
