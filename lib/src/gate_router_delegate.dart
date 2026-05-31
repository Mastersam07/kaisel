import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'gate_config.dart';
import 'gate_inner_navigator.dart';
import 'gate_route.dart';
import 'gate_router.dart';
import 'gate_scope.dart';

/// Signature for the function that turns a route into a screen.
///
/// Use Dart's pattern matching here — the compiler will enforce
/// exhaustiveness over your sealed route type:
///
/// ```dart
/// Widget buildPage(BuildContext context, AppRoute route) => switch (route) {
///   Home() => const HomeScreen(),
///   ProductDetail(:final id) => ProductDetailScreen(id: id),
/// };
/// ```
typedef GatePageBuilder<R extends GateRoute> = Widget Function(
  BuildContext context,
  R route,
);

/// Optional signature for customising how a route becomes a [Page].
///
/// Defaults to wrapping in a [MaterialPage]. Override to use
/// [CupertinoPage], custom transitions, or fullscreen-dialog routes.
typedef GatePageWrapper<R extends GateRoute> = Page<Object?> Function(
  R route,
  Widget child,
  LocalKey key,
);

/// Signature for rendering a modal flow over the main UI.
///
/// Given the [GateModalRoute] that defined the flow (so you can pattern
/// match on which flow it is) and a [flowChild] (the Navigator driving
/// the flow's own stack), return a widget to overlay on top of the main
/// UI — typically a [Dialog], [BottomSheet], or full-screen page.
///
/// The [flowChild] is already wired up to its own router; just wrap it
/// in whatever presentation you want.
typedef GateModalBuilder = Widget Function(
  BuildContext context,
  GateModalRoute<Object?> flowRoute,
  Widget flowChild,
);

/// The renderer over a [GateRouter].
///
/// Listens to the router for changes and rebuilds a [Navigator] with
/// the current stack of pages. When a modal flow is active, also
/// renders the flow's UI overlaid on top via [modalBuilder].
///
/// Installs a [RouterScope] at the root of its widget tree so
/// `context.router<R>()` resolves correctly anywhere in the app, and a
/// [GateNestedHostScope] so a mounted [GateBranchedShell] or
/// [GateModuleMount] can register itself for URL capture/restore.
class GateRouterDelegate<R extends GateRoute>
    extends RouterDelegate<GateConfig<R>>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<GateConfig<R>>
    implements GateNestedHost {
  /// Create a delegate driving [router].
  ///
  /// [builder] resolves a route to a widget — use pattern matching here
  /// so the compiler enforces exhaustiveness over your sealed type.
  ///
  /// [pageWrapper] optionally customises how the widget becomes a
  /// [Page]; defaults to a [MaterialPage].
  ///
  /// [modalBuilder] is required if your app uses modal flows
  /// (`router.run<T>(...)`). It's the user-supplied recipe for how a
  /// flow's UI is overlaid on top of the main stack.
  GateRouterDelegate({
    required this.router,
    required this.builder,
    this.pageWrapper,
    this.modalBuilder,
  }) {
    router.addListener(_safeNotifyListeners);
  }

  /// The router whose state drives this delegate.
  final GateRouter<R> router;

  /// Resolves a route to a widget.
  final GatePageBuilder<R> builder;

  /// Optional customiser for the [Page] wrapping. Defaults to
  /// [MaterialPage].
  final GatePageWrapper<R>? pageWrapper;

  /// Optional builder that renders an active modal flow over the main
  /// UI. Required if your app uses `router.run<T>(...)`.
  final GateModalBuilder? modalBuilder;

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final GlobalKey<NavigatorState> _flowNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'gate-flow');

  //
  // A mounted nested router (branched shell or module mount) registers
  // itself here. The host treats the most recently registered handle
  // as active — its config rides the URL. If a URL with nested state
  // arrives before a matching handle registers (cold-start deep link),
  // the state is queued in _pendingNested and applied when a handle
  // whose configType matches the pending config's runtime type
  // registers.

  final List<GateNestedHandle> _nested = <GateNestedHandle>[];
  GateNestedConfig? _pendingNested;
  bool _isDisposed = false;

  GateNestedHandle? get _activeNested => _nested.isEmpty ? null : _nested.last;

  /// Notify our listeners, deferring to after the current frame if
  /// we're called from inside a build/layout/paint callback.
  ///
  /// The Router widget that owns this delegate listens to us and
  /// synchronously calls `setState` in response. When a nested
  /// router's State.didChangeDependencies fires during build and
  /// triggers `registerNested`, a direct `notifyListeners()` would
  /// reach that listener mid-build and throw "setState called during
  /// build". Deferring sidesteps that without losing the update: the
  /// post-frame callback fires before the next frame, and the URL bar
  /// catches up one tick later.
  void _safeNotifyListeners() {
    if (_isDisposed) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    final inFrame = phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (inFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  @override
  void registerNested(GateNestedHandle handle) {
    // De-duplicate by identity; re-registering moves the handle to
    // the top of the stack (becomes active).
    final existing = _nested.indexWhere((h) => identical(h, handle));
    if (existing >= 0 && existing == _nested.length - 1) {
      return;
    }
    if (existing >= 0) {
      _nested.removeAt(existing);
    } else {
      handle.addListener(_safeNotifyListeners);
    }
    _nested.add(handle);

    final pending = _pendingNested;
    if (pending != null && handle.configType == pending.runtimeType) {
      _pendingNested = null;
      handle.restoreFromConfig(pending);
    }
    _safeNotifyListeners();
  }

  @override
  void unregisterNested(GateNestedHandle handle) {
    final index = _nested.indexWhere((h) => identical(h, handle));
    if (index < 0) return;
    _nested.removeAt(index);
    handle.removeListener(_safeNotifyListeners);
    _safeNotifyListeners();
  }

  @override
  GateConfig<R> get currentConfiguration => GateConfig<R>(
        mainStack: router.stack,
        nestedState: _activeNested?.captureConfig(),
      );

  @override
  Future<void> setNewRoutePath(GateConfig<R> configuration) async {
    if (configuration.mainStack.isEmpty) return;
    await router.applyFromInformation(configuration.mainStack);
    final nestedState = configuration.nestedState;
    if (nestedState == null) return;

    // Find a registered handle whose configType matches the incoming
    // config's runtime type. Prefer the most recently registered (the
    // active one) — that's the handle riding the URL.
    GateNestedHandle? match;
    for (var i = _nested.length - 1; i >= 0; i--) {
      if (_nested[i].configType == nestedState.runtimeType) {
        match = _nested[i];
        break;
      }
    }
    if (match != null) {
      await match.restoreFromConfig(nestedState);
    } else {
      // No matching handle yet (cold-start deep link into a nested
      // router that hasn't mounted). Queue for when one registers.
      _pendingNested = nestedState;
    }
  }

  // popRoute is supplied by PopNavigatorRouterDelegateMixin. The default
  // calls navigatorKey.currentState?.maybePop(), which runs route-level
  // willPop hooks and ultimately fires onDidRemovePage, which syncs the
  // router state. Don't override it to "fall back" to router.pop() — a
  // false return from maybePop means the route declined to pop (or there
  // is no nav state), and we should respect that, not force-pop.

  @override
  Widget build(BuildContext context) {
    final mainNavigator = Navigator(
      key: navigatorKey,
      pages: [
        for (final entry in router.entries)
          _wrap(context, entry.route, ValueKey<int>(entry.id)),
      ],
      onDidRemovePage: _onDidRemovePage,
    );

    Widget content = mainNavigator;

    final flowRoute = router.activeFlowRoute;
    final flowRouter = router.activeFlowRouter;
    if (flowRoute != null && flowRouter != null) {
      if (modalBuilder == null) {
        throw FlutterError(
          'A modal flow is active but no modalBuilder was provided to '
          'GateRouterDelegate. Pass modalBuilder: (context, route, child) '
          '=> ... when using router.run<T>(...).',
        );
      }
      content = _ModalOverlay<R>(
        mainContent: mainNavigator,
        flowRouter: flowRouter,
        flowRoute: flowRoute,
        flowNavigatorKey: _flowNavigatorKey,
        pageBuilder: builder,
        pageWrapper: pageWrapper,
        modalBuilder: modalBuilder!,
        onComplete: (value) => router.completeFlow<Object>(value),
      );
    }

    content = RouterScope<R>(router: router, child: content);
    // Install the host scope so descendant nested routers (branched
    // shells and module mounts) can register for URL capture/restore.
    return GateNestedHostScope(host: this, child: content);
  }

  Page<Object?> _wrap(BuildContext context, R route, LocalKey key) {
    final child = Builder(
      builder: (innerContext) => builder(innerContext, route),
    );
    final wrapper = pageWrapper;
    if (wrapper case final wrapper?) {
      return wrapper(route, child, key);
    }
    return MaterialPage<Object?>(key: key, child: child);
  }

  void _onDidRemovePage(Page<Object?> page) {
    // See notes in v0.4: Navigator-driven pops sync our state, but
    // guards do NOT rerun on this path — that's by design.
    final key = page.key;
    if (key is! ValueKey<int>) return;
    router.onPageRemoved(key.value);
  }

  @override
  void dispose() {
    _isDisposed = true;
    router.removeListener(_safeNotifyListeners);
    for (final handle in _nested) {
      handle.removeListener(_safeNotifyListeners);
    }
    _nested.clear();
    super.dispose();
  }
}

/// Inherited widget that exposes a [GateNestedHost] (the delegate) to
/// descendants. A mounted [GateBranchedShell] or [GateModuleMount]
/// looks this up to register itself for URL capture/restore.
///
/// Not exported from `package:gate/gate.dart` — typical apps don't
/// need to reference it.
class GateNestedHostScope extends InheritedWidget {
  /// Create a scope around [child] exposing [host].
  const GateNestedHostScope({
    super.key,
    required this.host,
    required super.child,
  });

  /// The host (typically the [GateRouterDelegate]).
  final GateNestedHost host;

  /// Look up the nearest host, or `null` if none is mounted (e.g.
  /// unit tests that mount a nested router outside a delegate).
  static GateNestedHost? maybeOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<GateNestedHostScope>();
    return scope?.host;
  }

  @override
  bool updateShouldNotify(GateNestedHostScope old) =>
      !identical(old.host, host);
}

/// Renders the main content with a modal flow overlaid on top.
///
/// Handles back-button routing: if the flow's stack has depth, back
/// pops within the flow; at flow root, back dismisses the flow.
class _ModalOverlay<R extends GateRoute> extends StatelessWidget {
  const _ModalOverlay({
    required this.mainContent,
    required this.flowRouter,
    required this.flowRoute,
    required this.flowNavigatorKey,
    required this.pageBuilder,
    required this.pageWrapper,
    required this.modalBuilder,
    required this.onComplete,
  });

  final Widget mainContent;
  final GateRouter<R> flowRouter;
  final GateModalRoute<Object?> flowRoute;
  final GlobalKey<NavigatorState> flowNavigatorKey;
  final GatePageBuilder<R> pageBuilder;
  final GatePageWrapper<R>? pageWrapper;
  final GateModalBuilder modalBuilder;

  /// Called when the flow should be resolved. `null` = dismissed,
  /// any other value = explicit completion.
  final void Function(Object? value) onComplete;

  @override
  Widget build(BuildContext context) {
    final flowNavigator = GateInnerNavigator<R>(
      router: flowRouter,
      navigatorKey: flowNavigatorKey,
      pageBuilder: pageBuilder,
      pageWrapper: pageWrapper,
    );

    final flowWithScopes = RouterScope<R>(
      router: flowRouter,
      child: FlowScope(
        onComplete: onComplete,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (flowRouter.canPop) {
              flowRouter.pop();
            } else {
              onComplete(null);
            }
          },
          child: flowNavigator,
        ),
      ),
    );

    final flowUi = modalBuilder(context, flowRoute, flowWithScopes);

    return Stack(children: [mainContent, flowUi]);
  }
}
