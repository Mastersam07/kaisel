import 'package:flutter/foundation.dart'
    show ValueListenable, kDebugMode, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
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
    this.rootPopsParent = false,
    this.closesOverlaysOnBack = false,
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

  /// Whether back on this navigator's first page leaves the page that hosts
  /// it, the way it would if the first page sat directly on the parent stack.
  ///
  /// Shells and module mounts set this. Their first page has nothing below it
  /// in its own [Navigator], so without it an [AppBar] there shows no back
  /// arrow even though the system back button would leave the shell. When the
  /// hosting page can be popped, the first page gets a back arrow, and tapping
  /// it pops the hosting page.
  final bool rootPopsParent;

  /// Whether system back first closes a drawer or other local history entry
  /// open on this navigator's top page, before anything is popped.
  ///
  /// Shells and module mounts set this. System back reaches the hosting page,
  /// not this navigator, so without it an open drawer is skipped and the page
  /// under it (or the whole host) is popped. Only kaisel's default pages
  /// report open drawers; a custom `pageWrapper` keeps the old behaviour.
  final bool closesOverlaysOnBack;

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
    _registerProbe();
  }

  void _registerProbe() {
    if (widget.closesOverlaysOnBack) {
      _overlayProbes[widget.router] = () => _overlayOpen;
    }
  }

  KaiselWebTransition _webTransition = KaiselWebTransition.fade;
  bool _androidPredictiveBack = false;
  final _absorbedChangeReporter = KaiselAbsorbedChangeReporter();

  Object? _host;

  void _registerWithHost(Object? host) {
    if (identical(host, _host)) return;
    if (_host case final old?) _backTargets[old]?.remove(this);
    _host = host;
    if (host != null) (_backTargets[host] ??= {}).add(this);
  }

  // Whether back should go to this navigator before the hosting page: it's
  // the visible branch, every route above it is on top, and its top page is
  // holding a local history entry (a drawer, a sheet, the back arrow's).
  bool get _takesBackFirst {
    if (!mounted || !TickerMode.valuesOf(context).enabled) return false;
    if (_routes[_topKey]?.willHandlePopInternally != true) return false;
    BuildContext? level = context;
    while (level != null) {
      final route = ModalRoute.of(level);
      if (route == null) break;
      if (!route.isCurrent) return false;
      level = route.navigator?.context;
    }
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.closesOverlaysOnBack) {
      _registerWithHost(KaiselNestedHostScope.maybeOf(context));
    }
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
      _overlayProbes[oldWidget.router] = null;
    }
    _registerProbe();
    if (!listEquals(oldWidget.observers, widget.observers)) _mergeObservers();
  }

  @override
  void dispose() {
    widget.router.removeListener(_onChange);
    _topOverlays?.removeListener(_onOverlaysChanged);
    if (widget.closesOverlaysOnBack) _overlayProbes[widget.router] = null;
    _registerWithHost(null);
    super.dispose();
  }

  ModalRoute<Object?>? _parent;

  ModalRoute<Object?>? _rootRoute;
  final Map<LocalKey, ModalRoute<Object?>> _routes = {};
  LocalKey? _topKey;
  ValueListenable<int>? _topOverlays;

  void _reportRoute(LocalKey key, int position, ModalRoute<Object?>? route) {
    if (route == null) {
      final gone = _routes.remove(key);
      if (position == 0 && identical(gone, _rootRoute)) _rootRoute = null;
    } else {
      _routes[key] = route;
      if (position == 0) _rootRoute = route;
    }
    _followTop();
  }

  void _followTop() {
    final overlays = switch (_routes[_topKey]) {
      final KaiselLocalHistoryTracker tracker => tracker.foreignLocalHistory,
      _ => null,
    };
    if (identical(overlays, _topOverlays)) return;
    _topOverlays?.removeListener(_onOverlaysChanged);
    _topOverlays = overlays?..addListener(_onOverlaysChanged);
  }

  bool get _overlayOpen => (_topOverlays?.value ?? 0) > 0;

  bool get _canHandlePop {
    final veto = _rootRoute?.popDisposition == RoutePopDisposition.doNotPop;
    if (_parent?.impliesAppBarDismissal == true) {
      return widget.router.canPop || veto || _overlayOpen;
    }
    return (widget.navigatorKey.currentState?.canPop() ?? false) || veto;
  }

  // Opening a drawer sends no NavigationNotification, so rebuild the PopScope
  // and tell hosts that back can now be handled here.
  void _onOverlaysChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onOverlaysChanged());
      return;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      NavigationNotification(canHandlePop: _canHandlePop).dispatch(context);
    });
  }

  // AppBar picks a close button over a back arrow only when its own route is
  // a fullscreen dialog, so the first page mirrors a host opened as one.
  bool get _hostIsFullscreenDialog => switch (_parent) {
    final PageRoute<Object?> host =>
      host.fullscreenDialog && host.impliesAppBarDismissal,
    _ => false,
  };

  KaiselPageWrapperContext<R> _bridgeRoot(KaiselPageWrapperContext<R> ctx) {
    final parent = _parent;
    if (parent == null && !widget.closesOverlaysOnBack) return ctx;
    Widget child = ctx.child;
    if (parent != null && ctx.position == 0) {
      child = _ParentPopBridge(
        parent: parent,
        enabled: parent.impliesAppBarDismissal,
        child: child,
      );
    }
    return KaiselPageWrapperContext<R>(
      route: ctx.route,
      child: _RouteReporter(
        pageKey: ctx.key,
        position: ctx.position,
        onRoute: _reportRoute,
        child: child,
      ),
      key: ctx.key,
      position: ctx.position,
      stackLength: ctx.stackLength,
      previous: ctx.previous,
      isFlow: ctx.isFlow,
    );
  }

  Page<Object?> _wrapSimple(KaiselPageWrapperContext<R> raw) {
    final ctx = _bridgeRoot(raw);
    final wrapper = widget.pageWrapper;
    if (wrapper case final wrapper?) return wrapper(ctx);
    return kaiselDefaultPage(
      ctx,
      transition: _webTransition,
      androidPredictiveBack: _androidPredictiveBack,
      fullscreenDialog: ctx.position == 0 && _hostIsFullscreenDialog,
    );
  }

  Page<Object?> _wrapAdaptive(KaiselPageWrapperContext<R> raw) {
    final ctx = _bridgeRoot(raw);
    final wrapper = widget.pageWrapper;
    if (wrapper case final wrapper?) return wrapper(ctx);
    return kaiselDefaultPage(
      ctx,
      transition: _webTransition,
      androidPredictiveBack: _androidPredictiveBack,
      fullscreenDialog: ctx.position == 0 && _hostIsFullscreenDialog,
    );
  }

  @override
  Widget build(BuildContext context) {
    _parent = widget.rootPopsParent ? ModalRoute.of(context) : null;
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
    _topKey = pages.isEmpty ? null : pages.last.key;
    _followTop();

    final navigator = HeroControllerScope(
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
    // The bridge's entry makes the Navigator claim it can handle back even at
    // its root, which would make the branched shell swallow a back that should
    // leave it. Report the answer without that entry.
    final reported = NotificationListener<NavigationNotification>(
      onNotification: (notification) {
        if (_parent?.impliesAppBarDismissal != true) return false;
        final canHandlePop = _canHandlePop;
        if (notification.canHandlePop == canHandlePop) return false;
        NavigationNotification(canHandlePop: canHandlePop).dispatch(context);
        return true;
      },
      child: navigator,
    );
    if (!widget.closesOverlaysOnBack) return reported;
    // This sits above the Navigator, so it registers on the hosting page's
    // route, where system back lands. Hosts check [kaiselHasOpenOverlay] so they
    // don't also pop the page under the drawer.
    final closing = _overlayOpen && TickerMode.valuesOf(context).enabled;
    return PopScope<Object?>(
      canPop: !closing,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_overlayOpen) return;
        if (!TickerMode.valuesOf(context).enabled) return;
        widget.navigatorKey.currentState?.maybePop();
      },
      child: reported,
    );
  }
}

final Expando<Set<_KaiselInnerNavigatorState<KaiselRoute>>> _backTargets =
    Expando<Set<_KaiselInnerNavigatorState<KaiselRoute>>>(
      'kaisel back targets',
    );

/// Offers system back to the deepest nested navigator under [host] whose top
/// page holds a local history entry, such as an open drawer, and reports
/// whether it was handled.
///
/// Framework-facing: the delegate calls this before popping its own stack.
/// It works for any page type, so a custom `pageWrapper` page gets its drawer
/// closed too, which drawer tracking alone can't do.
Future<bool> kaiselPopNestedOverlay(Object host) async {
  _KaiselInnerNavigatorState<KaiselRoute>? deepest;
  var depth = -1;
  for (final target in _backTargets[host] ?? const <Never>{}) {
    if (!target._takesBackFirst) continue;
    final targetDepth = (target.context as Element).depth;
    if (targetDepth <= depth) continue;
    deepest = target;
    depth = targetDepth;
  }
  final navigator = deepest?.widget.navigatorKey.currentState;
  if (navigator == null) return false;
  return navigator.maybePop();
}

final Expando<bool Function()> _overlayProbes = Expando<bool Function()>(
  'kaisel open overlay',
);

/// Whether the navigator driven by [router] has a drawer or other local
/// history entry open on its top page, which back should close first.
///
/// Framework-facing: shells and module mounts check it before popping their
/// router on back, so the page under an open drawer stays.
bool kaiselHasOpenOverlay(Object router) =>
    _overlayProbes[router]?.call() ?? false;

class _RouteReporter extends StatefulWidget {
  const _RouteReporter({
    required this.pageKey,
    required this.position,
    required this.onRoute,
    required this.child,
  });

  final LocalKey pageKey;
  final int position;
  final void Function(LocalKey key, int position, ModalRoute<Object?>? route)
  onRoute;
  final Widget child;

  @override
  State<_RouteReporter> createState() => _RouteReporterState();
}

class _RouteReporterState extends State<_RouteReporter> {
  ModalRoute<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(route, _route)) return;
    _route = route;
    widget.onRoute(widget.pageKey, widget.position, route);
  }

  @override
  void didUpdateWidget(_RouteReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      widget.onRoute(widget.pageKey, widget.position, _route);
    }
  }

  @override
  void dispose() {
    widget.onRoute(widget.pageKey, widget.position, null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// AppBar shows a back arrow for a route with a local history entry, and
// BackButton removes the entry first, so an entry on the first page gives it an
// arrow whose tap pops the hosting page instead.
class _ParentPopBridge extends StatefulWidget {
  const _ParentPopBridge({
    required this.parent,
    required this.enabled,
    required this.child,
  });

  final ModalRoute<Object?> parent;
  final bool enabled;
  final Widget child;

  @override
  State<_ParentPopBridge> createState() => _ParentPopBridgeState();
}

class _ParentPopBridgeState extends State<_ParentPopBridge> {
  ModalRoute<Object?>? _route;
  LocalHistoryEntry? _entry;
  bool _added = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!identical(route, _route)) {
      _detach();
      _route = route;
    }
    _sync();
  }

  @override
  void didUpdateWidget(_ParentPopBridge oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _sync() => widget.enabled ? _attach() : _detach();

  void _attach() {
    if (_entry != null) return;
    late final LocalHistoryEntry entry;
    entry = KaiselParentPopEntry(
      onRemove: () {
        if (!identical(_entry, entry)) return;
        _entry = null;
        _added = false;
        final parent = widget.parent;
        if (parent.isCurrent) parent.navigator?.maybePop();
      },
    );
    _entry = entry;
    // Adding an entry rebuilds the route, which can't happen mid build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final route = _route;
      if (!mounted || !identical(_entry, entry) || route == null) return;
      if (!route.isActive) return;
      route.addLocalHistoryEntry(entry);
      _added = true;
    });
  }

  void _detach() {
    final entry = _entry;
    final route = _route;
    final added = _added;
    _entry = null;
    _added = false;
    if (entry == null || !added || route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isActive) route.removeLocalHistoryEntry(entry);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
