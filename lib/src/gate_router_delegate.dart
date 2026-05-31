import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'gate_adaptive.dart';
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
  /// [builder] resolves a route to a widget. Use pattern matching here
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
    required GatePageBuilder<R> builder,
    this.pageWrapper,
    this.modalBuilder,
  })  : _builder = builder,
        _adaptiveBuilder = null {
    router.addListener(_safeNotifyListeners);
  }

  /// Create a delegate that uses an adaptive builder for the main
  /// stack.
  ///
  /// The adaptive builder receives a [GateStackContext] for each
  /// entry so it can pattern-match on neighbours and decide whether
  /// to render a standalone or absorbing page. A typical use is
  /// master-detail at wide breakpoints: the detail route absorbs
  /// the master into one rendered page.
  ///
  /// ```dart
  /// GateRouterDelegate.adaptive(
  ///   router: router,
  ///   builder: (context, route, stack) {
  ///     final wide = MediaQuery.sizeOf(context).width >= 700;
  ///     return switch ((route, stack.previous, wide)) {
  ///       (ProductDetail(:final id), ProductList(), true) =>
  ///         GateAbsorbingPage(
  ///           widget: GateMasterDetailScaffold(
  ///             master: const ProductListScreen(),
  ///             detail: ProductDetailScreen(id: id),
  ///           ),
  ///           absorbing: 1,
  ///         ),
  ///       _ => GateStandalonePage(buildSimple(route)),
  ///     };
  ///   },
  /// );
  /// ```
  ///
  /// Modal flows still run through the simple per-route flow inside
  /// `modalBuilder`. The adaptive builder is consulted only for the
  /// main Navigator's stack. When a modal flow is active, each of
  /// its routes is built by calling the adaptive builder with a
  /// single-entry stack context and using just the widget; the
  /// `absorbing` count is ignored in that path.
  ///
  /// New in v0.8.
  GateRouterDelegate.adaptive({
    required this.router,
    required GateAdaptivePageBuilder<R> builder,
    this.pageWrapper,
    this.modalBuilder,
  })  : _builder = null,
        _adaptiveBuilder = builder {
    router.addListener(_safeNotifyListeners);
  }

  /// The router whose state drives this delegate.
  final GateRouter<R> router;

  /// Simple page builder (v0.7 style). Null when [GateRouterDelegate.adaptive]
  /// was used.
  final GatePageBuilder<R>? _builder;

  /// Adaptive page builder (v0.8). Null when the default constructor
  /// was used.
  final GateAdaptivePageBuilder<R>? _adaptiveBuilder;

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

  /// Number of pages produced by the most recent build of the main
  /// navigator. Used by [popRoute] to detect adaptive absorbing
  /// states where the Navigator has fewer visible pages than the
  /// router has logical entries.
  int _lastBuiltMainPageCount = 0;

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

  // popRoute is supplied by PopNavigatorRouterDelegateMixin by default
  // and just calls navigatorKey.currentState?.maybePop(). For the
  // simple builder path that's still correct: maybePop runs route
  // willPop hooks and ultimately fires onDidRemovePage, which syncs
  // the router state. A false return means the route declined (or
  // there's no navigator), and we respect that, not force-pop.
  //
  // In adaptive mode the Navigator can hold fewer visible pages than
  // the router has logical entries (a `GateAbsorbingPage` collapses
  // entries below). When absorption collapses everything to a single
  // visible page, [Navigator.maybePop] returns false because there's
  // no route below it (its internal `canPop` requires a route below
  // the current one), and `onDidRemovePage` never fires. The OS back
  // gesture would then bubble out of the app instead of unwinding
  // the logical stack. Override [popRoute] to detect that case and
  // pop the router directly.

  @override
  Future<bool> popRoute() async {
    final navState = navigatorKey.currentState;
    if (navState == null) return false;

    final popped = await navState.maybePop();
    if (popped) return true;

    if (_adaptiveBuilder != null &&
        router.canPop &&
        _lastBuiltMainPageCount < router.entries.length) {
      return router.pop();
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final entries = router.entries;
    final mainPages = _adaptiveBuilder != null
        ? _adaptiveMainPages(context, entries)
        : _simpleMainPages(context, entries);

    _lastBuiltMainPageCount = mainPages.length;

    final mainNavigator = Navigator(
      key: navigatorKey,
      pages: mainPages,
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
        pageBuilder: _effectiveSimpleBuilder,
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

  List<Page<Object?>> _simpleMainPages(
    BuildContext context,
    List<GateStackEntry<R>> entries,
  ) {
    return [
      for (final entry in entries)
        _wrapSimple(context, entry.route, ValueKey<int>(entry.id)),
    ];
  }

  List<Page<Object?>> _adaptiveMainPages(
    BuildContext context,
    List<GateStackEntry<R>> entries,
  ) {
    final adaptive = _adaptiveBuilder!;
    final stack = [for (final e in entries) e.route];
    final pages = <Page<Object?>>[];
    var i = stack.length - 1;

    while (i >= 0) {
      final ctx = GateStackContext<R>(stack: stack, position: i);
      final result = adaptive(context, stack[i], ctx);

      switch (result) {
        case GateStandalonePage(:final widget):
          pages.insert(
            0,
            _wrapAdaptive(
              stack[i],
              _AdaptiveKey(entries[i].id, entries[i].id),
              widget,
            ),
          );
          i--;
        case GateAbsorbingPage(:final widget, :final absorbing):
          var lowestIdx = i - absorbing;
          if (lowestIdx < 0) {
            // Pathological: route asked to absorb more entries than
            // exist below it. Clamp to absorbing what's available.
            // Helpful for tests; users shouldn't hit this in real
            // apps unless their pattern-match is wrong.
            assert(
              false,
              'GateAbsorbingPage(absorbing: $absorbing) at position $i '
              'overflows the stack of length ${stack.length}',
            );
            lowestIdx = 0;
          }
          // Page identity uses the lowest absorbed entry's id so that
          // toggling absorbed/standalone (or swapping detail-A for
          // detail-B) doesn't trigger a Navigator transition. The
          // popId is the top absorbing entry's id so the OS back
          // gesture pops the top, not the lowest.
          pages.insert(
            0,
            _wrapAdaptive(
              stack[i],
              _AdaptiveKey(entries[lowestIdx].id, entries[i].id),
              widget,
            ),
          );
          i = lowestIdx - 1;
      }
    }

    return pages;
  }

  /// The simple builder used by the modal-flow inner navigator. When
  /// the delegate was constructed with an adaptive builder, synthesise
  /// one by calling the adaptive builder on a single-entry stack and
  /// using its widget. Modal flow screens are always rendered as
  /// standalone; `absorbing` is ignored on this path.
  GatePageBuilder<R> get _effectiveSimpleBuilder {
    final simple = _builder;
    if (simple != null) return simple;
    final adaptive = _adaptiveBuilder!;
    return (BuildContext context, R route) {
      final ctx = GateStackContext<R>(stack: [route], position: 0);
      return adaptive(context, route, ctx).widget;
    };
  }

  Page<Object?> _wrapSimple(BuildContext context, R route, LocalKey key) {
    final child = Builder(
      builder: (innerContext) => _builder!(innerContext, route),
    );
    final wrapper = pageWrapper;
    if (wrapper case final wrapper?) {
      return wrapper(route, child, key);
    }
    return MaterialPage<Object?>(key: key, child: child);
  }

  Page<Object?> _wrapAdaptive(R route, LocalKey key, Widget widget) {
    final wrapper = pageWrapper;
    if (wrapper case final wrapper?) {
      return wrapper(route, widget, key);
    }
    return MaterialPage<Object?>(key: key, child: widget);
  }

  void _onDidRemovePage(Page<Object?> page) {
    // See notes in v0.4: Navigator-driven pops sync our state, but
    // guards do NOT rerun on this path. That's by design.
    final key = page.key;
    if (key is _AdaptiveKey) {
      router.onPageRemoved(key.popId);
      return;
    }
    if (key is ValueKey<int>) {
      router.onPageRemoved(key.value);
    }
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

/// Page key used by the adaptive pipeline. Carries two integer ids:
/// [stableId] (used for [Navigator] page identity) and [popId] (used
/// by `_onDidRemovePage` to figure out which router entry to drop on
/// an OS back gesture).
///
/// For standalone pages they're identical: the page's own entry id.
/// For absorbing pages [stableId] is the lowest absorbed entry's id
/// (so toggling absorbed/standalone preserves Navigator identity),
/// and [popId] is the top absorbing entry's id (so OS back pops the
/// top of the logical stack, not the lowest absorbed entry).
///
/// Equality and hashCode use only [stableId]; [popId] is opaque to
/// [Navigator]. This is what gives master-detail its in-place feel:
/// `[List, DetailA]` and `[List, DetailB]` produce equal keys, so
/// Navigator doesn't animate between them.
@immutable
class _AdaptiveKey extends LocalKey {
  const _AdaptiveKey(this.stableId, this.popId);

  final int stableId;
  final int popId;

  @override
  bool operator ==(Object other) =>
      other is _AdaptiveKey && other.stableId == stableId;

  @override
  int get hashCode => stableId.hashCode;

  @override
  String toString() => '_AdaptiveKey(stable: $stableId, pop: $popId)';
}
