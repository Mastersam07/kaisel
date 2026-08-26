import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:kaisel_core/framework.dart';

import 'kaisel_adaptive.dart';
import 'kaisel_branched_shell.dart';
import 'kaisel_default_page.dart';
import 'kaisel_inner_navigator.dart';
import 'kaisel_page_scope.dart';
import 'kaisel_page_wrapper.dart';
import 'kaisel_screen_signal.dart';
import 'kaisel_scope.dart';
import 'kaisel_stack_restorer.dart';

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
typedef KaiselPageBuilder<R extends KaiselRoute> =
    Widget Function(BuildContext context, R route);

/// Signature for rendering a modal flow over the main UI.
///
/// Given the [KaiselModalRoute] that defined the flow (so you can pattern
/// match on which flow it is) and a [flowChild] (the Navigator driving
/// the flow's own stack), return a widget to overlay on top of the main
/// UI — typically a [Dialog], [BottomSheet], or full-screen page.
///
/// The [flowChild] is already wired up to its own router and wrapped in a
/// transparent [Material], so flow screens can use material widgets
/// ([ListTile], [TextField], ...) without providing a [Scaffold]; just wrap
/// it in whatever presentation you want.
typedef KaiselModalBuilder =
    Widget Function(
      BuildContext context,
      KaiselModalRoute<Object?> flowRoute,
      Widget flowChild,
    );

/// Builds the [NavigatorObserver]s for one navigator.
///
/// kaisel calls this **once per navigator** — the main stack, and each nested
/// shell branch, module, and flow — so every navigator gets its **own fresh
/// instances**. A [NavigatorObserver] belongs to a single [Navigator], so the
/// builder must return new instances on each call; don't hand back a shared
/// instance. The result is cached per navigator, so it isn't rebuilt on every
/// frame.
///
/// ```dart
/// KaiselRouterConfig(
///   observers: () => [MyAnalyticsObserver()],
///   ...
/// );
/// ```
typedef KaiselObserversBuilder = List<NavigatorObserver> Function();

/// Carries the app's [KaiselObserversBuilder] down the tree. Installed by
/// [KaiselRouterDelegate] so that nested navigators (shell branches, modules,
/// flows) can attach their own fresh observers. You don't use this directly.
class KaiselObserverScope extends InheritedWidget {
  /// Create the scope with the app's [observers] builder and, when the app
  /// asked for one, the [screenReporter] every visible navigator feeds.
  const KaiselObserverScope({
    super.key,
    required this.observers,
    this.screenReporter,
    required super.child,
  });

  /// The builder, or null when the app supplied no observers.
  final KaiselObserversBuilder? observers;

  /// The app-level screen signal, or null when no `onScreenChanged` was given.
  final KaiselScreenReporter? screenReporter;

  /// The nearest builder, or null if none is installed.
  static KaiselObserversBuilder? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<KaiselObserverScope>()
      ?.observers;

  /// The nearest screen reporter, or null if none is installed.
  static KaiselScreenReporter? reporterOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<KaiselObserverScope>()
      ?.screenReporter;

  @override
  bool updateShouldNotify(KaiselObserverScope oldWidget) =>
      !identical(oldWidget.observers, observers) ||
      !identical(oldWidget.screenReporter, screenReporter);
}

/// The renderer over a [KaiselRouter].
///
/// Listens to the router for changes and rebuilds a [Navigator] with
/// the current stack of pages. When a modal flow is active, also
/// renders the flow's UI overlaid on top via [modalBuilder].
///
/// Installs a [RouterScope] at the root of its widget tree so
/// `context.router<R>()` resolves correctly anywhere in the app, and a
/// [KaiselNestedHostScope] so a mounted [KaiselBranchedShell] or
/// [KaiselModuleMount] can register itself for URL capture/restore.
class KaiselRouterDelegate<R extends KaiselRoute>
    extends RouterDelegate<KaiselConfig<R>>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<KaiselConfig<R>>
    implements KaiselNestedHost, KaiselInspectable, KaiselListenable {
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
  KaiselRouterDelegate({
    required this.router,
    required KaiselPageBuilder<R> builder,
    this.pageWrapper,
    this.modalBuilder,
    this.observers,
    this.onScreenChanged,
    this.restorationScopeId,
    this.restoreRoute,
    this.webTransition = KaiselWebTransition.fade,
    this.androidPredictiveBack = false,
    GlobalKey<NavigatorState>? navigatorKey,
    KaiselConfigCodec<R>? codec,
  }) : _builder = builder,
       _adaptiveBuilder = null,
       navigatorKey = navigatorKey ?? GlobalKey<NavigatorState>(),
       _codec = codec {
    router.addListener(_onRootChanged);
    _registerWithInspector();
  }

  /// Create a delegate that uses an adaptive builder for the main
  /// stack.
  ///
  /// The adaptive builder receives a [KaiselStackContext] for each
  /// entry so it can pattern-match on neighbours and decide whether
  /// to render a standalone or absorbing page. A typical use is
  /// master-detail at wide breakpoints: the detail route absorbs
  /// the master into one rendered page.
  ///
  /// ```dart
  /// KaiselRouterDelegate.adaptive(
  ///   router: router,
  ///   builder: (context, route, stack) {
  ///     final wide = MediaQuery.sizeOf(context).width >= 700;
  ///     return switch ((route, stack.previous, wide)) {
  ///       (ProductDetail(:final id), ProductList(), true) =>
  ///         KaiselAbsorbingPage(
  ///           widget: KaiselMasterDetailScaffold(
  ///             master: const ProductListScreen(),
  ///             detail: ProductDetailScreen(id: id),
  ///           ),
  ///           absorbing: 1,
  ///         ),
  ///       _ => KaiselStandalonePage(buildSimple(route)),
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
  KaiselRouterDelegate.adaptive({
    required this.router,
    required KaiselAdaptivePageBuilder<R> builder,
    this.pageWrapper,
    this.modalBuilder,
    this.observers,
    this.onScreenChanged,
    this.restorationScopeId,
    this.restoreRoute,
    this.webTransition = KaiselWebTransition.fade,
    this.androidPredictiveBack = false,
    GlobalKey<NavigatorState>? navigatorKey,
    KaiselConfigCodec<R>? codec,
  }) : _builder = null,
       _adaptiveBuilder = builder,
       navigatorKey = navigatorKey ?? GlobalKey<NavigatorState>(),
       _codec = codec {
    router.addListener(_onRootChanged);
    _registerWithInspector();
  }

  /// The router whose state drives this delegate.
  final KaiselRouter<R> router;

  /// Simple page builder. Null when [KaiselRouterDelegate.adaptive]
  /// was used.
  final KaiselPageBuilder<R>? _builder;

  /// Adaptive page builder. Null when the default constructor
  /// was used.
  final KaiselAdaptivePageBuilder<R>? _adaptiveBuilder;

  /// The config codec, supplied by [KaiselRouterConfig] when the app is
  /// URL-addressable. Used only to encode the current configuration into the
  /// `url` field of the debug snapshot; null for URL-less apps.
  final KaiselConfigCodec<R>? _codec;

  /// Optional customiser for the [Page] wrapping. Defaults to
  /// [MaterialPage].
  final KaiselPageWrapper<R>? pageWrapper;

  /// The default page transition on the **web** when no [pageWrapper] is given.
  /// Defaults to [KaiselWebTransition.fade]; ignored off the web and when a
  /// [pageWrapper] is set.
  final KaiselWebTransition webTransition;

  /// Guarantee the default page's Android transition goes through Flutter's
  /// predictive-back builder, so a nested-navigator route follows the OS back
  /// gesture regardless of Flutter version (before Flutter 3.44, Android's
  /// default transition wasn't predictive) or `pageTransitionsTheme`
  /// overrides. Off by default — the
  /// theme decides. Ignored on the web and when a [pageWrapper] is set.
  ///
  /// The transition only matters where the OS delivers the back gesture at
  /// all: Android 14+, for apps opted in with
  /// `android:enableOnBackInvokedCallback="true"` on the manifest's
  /// `<application>` — the default once an app targets SDK 36 on Android 16.
  /// Android 13 accepts the flag but lacks the gesture-progress APIs, so no
  /// predictive animation shows there; Android 12 and below never engage it.
  final bool androidPredictiveBack;

  /// Optional builder that renders an active modal flow over the main
  /// UI. Required if your app uses `router.run<T>(...)`.
  final KaiselModalBuilder? modalBuilder;

  /// Builds the [NavigatorObserver]s for each navigator — e.g. an analytics or
  /// Sentry observer. Called once per navigator (main stack and each nested
  /// shell branch, module, and flow), so each gets its own fresh instances.
  /// Null for no observers. See [KaiselObserversBuilder].
  final KaiselObserversBuilder? observers;

  /// Passed to the main [Navigator.restorationScopeId]. Set it to give the main
  /// stack a restoration scope so its pages' inner widget state (via
  /// `RestorationMixin`) survives process death. The app must also have a
  /// `restorationScopeId` (e.g. on `MaterialApp`). Null disables it.
  final String? restorationScopeId;

  /// Rebuilds routes for codec-less stack restoration. When set, the **main**
  /// stack is saved to and restored from a `RestorationMixin` bucket — no URL
  /// codec needed. Use this *or* a `codec`, not both. The app must also have a
  /// `restorationScopeId` (e.g. on `MaterialApp`).
  final KaiselRouteRestorer<R>? restoreRoute;

  /// Called with the route the user is now looking at, once per change,
  /// wherever in the app it lives — the main stack, a shell branch, a module,
  /// or a modal flow.
  ///
  /// Unlike an [observers] instance, which belongs to one [Navigator] and so
  /// holds per-branch state, this is a single app-level signal: switching tab
  /// A → B → A reports each screen once, in order. Reach for it for
  /// screen-view analytics; reach for [observers] when a package expects a
  /// real [NavigatorObserver].
  final KaiselScreenCallback? onScreenChanged;

  late final KaiselScreenReporter? _screenReporter = switch (onScreenChanged) {
    final callback? => KaiselScreenReporter(callback),
    _ => null,
  };

  /// The main stack's observers, built once from [observers] and reused for the
  /// delegate's lifetime (so they aren't rebuilt every frame).
  late final List<NavigatorObserver> _mainObservers = [
    ...?observers?.call(),
    if (_screenReporter case final reporter?) KaiselScreenObserver(reporter),
  ];

  /// Key for the main [Navigator]. Pass one to reach the navigator imperatively
  /// (e.g. a third-party SDK that wants a `GlobalKey<NavigatorState>`); defaults
  /// to a freshly created key. For context-free *navigation*, prefer the typed
  /// `router` — the key is for raw `NavigatorState` access.
  @override
  final GlobalKey<NavigatorState> navigatorKey;

  /// Stable [GlobalKey]s for each active modal flow's inner Navigator.
  /// Indexed parallel to `router.activeFlows`. Grown lazily in [build]
  /// as flows are pushed and shrunk as they're completed (in LIFO
  /// order, matching the flow completion discipline).
  ///
  /// A single shared key wouldn't survive nested flows; reusing one
  /// across two simultaneous Navigators is one of Flutter's standard
  /// "two widgets have the same GlobalKey" assertions.
  final List<GlobalKey<NavigatorState>> _flowNavigatorKeys =
      <GlobalKey<NavigatorState>>[];

  //
  // A mounted nested router (branched shell or module mount) registers
  // itself here. The host treats the most recently registered handle
  // as active — its config rides the URL. If a URL with nested state
  // arrives before a matching handle registers (cold-start deep link),
  // the state is queued in _pendingNested and applied when a handle
  // whose configType matches the pending config's runtime type
  // registers.

  final List<KaiselNestedHandle> _nested = <KaiselNestedHandle>[];
  final Map<KaiselNestedHandle, VoidCallback> _nestedListeners = {};
  KaiselNestedConfig? _pendingNested;
  bool _isDisposed = false;

  bool _reportReplaces = false;

  /// Whether the next route-information report should overwrite the browser
  /// history entry rather than add one. Tracks the disposition of whichever
  /// router — the main router or the active nested (shell branch / module)
  /// router — committed the most recent change, so a nested `replaceTop` /
  /// `set` is reported as a replace too. Read by the
  /// route-information provider at report time.
  bool get replacesHistoryEntry => _reportReplaces;

  /// Number of pages produced by the most recent build of the main
  /// navigator. Used by [popRoute] to detect adaptive absorbing
  /// states where the Navigator has fewer visible pages than the
  /// router has logical entries.
  int _lastBuiltMainPageCount = 0;

  KaiselNestedHandle? get _activeNested =>
      _nested.isEmpty ? null : _nested.last;

  /// Notify our listeners on the next microtask, never
  /// synchronously.
  ///
  /// The Router widget that owns this delegate listens to us and
  /// synchronously calls `setState` in response. Any synchronous
  /// `notifyListeners` from a path that might be reached during a
  /// build (a nested host's didChangeDependencies during initial
  /// mount, a guard completing inside a build, a router push from
  /// initState, etc.) would reach the Router mid-build and throw
  /// "setState called during build".
  ///
  /// Earlier versions of this method gated on
  /// `SchedulerBinding.schedulerPhase`, but that check is
  /// insufficient: the initial widget tree attach happens via
  /// `WidgetsBinding.scheduleAttachRootWidget` → `Timer.run`,
  /// which fires outside any frame. The scheduler phase is `idle`
  /// during that timer's execution, but the `BuildOwner` is
  /// actively building widgets, so a synchronous notification
  /// still triggers the assertion.
  ///
  /// Deferring via `scheduleMicrotask` sidesteps the problem
  /// uniformly: microtasks drain as soon as the current
  /// synchronous block (including `BuildOwner.buildScope`)
  /// finishes. There's no observable difference for normal
  /// operation, since `setState` only marks the Router dirty for
  /// the next frame either way; the one-microtask delay before
  /// that happens is invisible.
  void _safeNotifyListeners() {
    if (_isDisposed) return;
    scheduleMicrotask(() {
      if (!_isDisposed) notifyListeners();
    });
  }

  /// Root-router change: capture its replace/push disposition for the next
  /// report, then notify. A nested handle does the same in [registerNested],
  /// so [_reportReplaces] always reflects whichever router committed last.
  void _onRootChanged() {
    _reportReplaces = router.replacesHistoryEntry;
    _safeNotifyListeners();
  }

  @override
  void registerNested(KaiselNestedHandle handle) {
    // De-duplicate by identity; re-registering moves the handle to
    // the top of the stack (becomes active).
    final existing = _nested.indexWhere((h) => identical(h, handle));
    if (existing >= 0 && existing == _nested.length - 1) {
      return;
    }
    if (existing >= 0) {
      _nested.removeAt(existing);
    } else {
      void listener() {
        _reportReplaces = handle.replacesHistoryEntry;
        _safeNotifyListeners();
      }

      _nestedListeners[handle] = listener;
      handle.addListener(listener);
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
  void unregisterNested(KaiselNestedHandle handle) {
    final index = _nested.indexWhere((h) => identical(h, handle));
    if (index < 0) return;
    _nested.removeAt(index);
    final listener = _nestedListeners.remove(handle);
    if (listener != null) handle.removeListener(listener);
    _safeNotifyListeners();
  }

  @override
  KaiselConfig<R> get currentConfiguration => KaiselConfig<R>(
    mainStack: router.stack,
    nestedState: _activeNested?.captureConfig(),
  );

  @override
  Future<void> setNewRoutePath(KaiselConfig<R> configuration) async {
    if (configuration.mainStack.isEmpty) return;
    await router.applyFromInformation(configuration.mainStack);
    final nestedState = configuration.nestedState;
    if (nestedState == null) return;

    // Find a registered handle whose configType matches the incoming
    // config's runtime type. Prefer the most recently registered (the
    // active one) — that's the handle riding the URL.
    KaiselNestedHandle? match;
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
  // the router has logical entries (a `KaiselAbsorbingPage` collapses
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
    Widget content = KaiselWebTransitionScope(
      transition: webTransition,
      androidPredictiveBack: androidPredictiveBack,
      child: KaiselObserverScope(
        observers: observers,
        screenReporter: _screenReporter,
        child: KaiselNestedHostScope(
          host: this,
          child: RouterScope<R>(
            router: router,
            child: _buildNavigator(context),
          ),
        ),
      ),
    );
    final restore = restoreRoute;
    if (restore != null) {
      content = KaiselStackRestorer<R>(
        router: router,
        restore: restore,
        child: content,
      );
    }
    return content;
  }

  /// Builds the single main [Navigator]. Its pages are the main stack
  /// followed by one transparent page per active modal flow, so a flow — and
  /// any dialog pushed above it — lives in the same overlay as everything
  /// else.
  Widget _buildNavigator(BuildContext context) {
    final entries = router.entries;
    final mainPages = switch (_adaptiveBuilder) {
      final builder? => _adaptiveMainPages(context, entries, builder),
      _ => _simpleMainPages(context, entries),
    };

    _lastBuiltMainPageCount = mainPages.length;

    final activeFlows = router.activeFlows;
    if (activeFlows.isNotEmpty && modalBuilder == null) {
      throw FlutterError(
        'A modal flow is active but no modalBuilder was provided to '
        'KaiselRouterDelegate. Pass modalBuilder: (context, route, child) '
        '=> ... when using router.run<T>(...).',
      );
    }

    while (_flowNavigatorKeys.length < activeFlows.length) {
      _flowNavigatorKeys.add(
        GlobalKey<NavigatorState>(
          debugLabel: 'kaisel-flow-${_flowNavigatorKeys.length}',
        ),
      );
    }
    while (_flowNavigatorKeys.length > activeFlows.length) {
      _flowNavigatorKeys.removeLast();
    }

    return Navigator(
      key: navigatorKey,
      observers: _mainObservers,
      restorationScopeId: restorationScopeId,
      onDidRemovePage: _onDidRemovePage,
      pages: <Page<Object?>>[
        ...mainPages,
        for (var i = 0; i < activeFlows.length; i++)
          _flowPage(
            i,
            mainPages.length,
            activeFlows.length,
            activeFlows[i],
            _flowPageChild(context, activeFlows[i], _flowNavigatorKeys[i]),
          ),
      ],
    );
  }

  /// Builds the outer page for an active flow. A `pageWrapper` can customise
  /// its entrance transition via an `isFlow` context; otherwise it is the
  /// instant, transparent [_FlowPage].
  Page<Object?> _flowPage(
    int flowIndex,
    int mainCount,
    int flowCount,
    KaiselActiveFlow<R> flow,
    Widget child,
  ) {
    final key = _FlowPageKey(flowIndex);
    final wrapper = pageWrapper;
    if (wrapper != null) {
      return wrapper(
        KaiselPageWrapperContext<R>(
          route: flow.route as R,
          child: child,
          key: key,
          position: mainCount + flowIndex,
          stackLength: mainCount + flowCount,
          isFlow: true,
        ),
      );
    }
    return _FlowPage(
      key: key,
      name: flow.route.routeName,
      arguments: flow.route,
      child: child,
    );
  }

  /// The content of a flow page: the flow's inner navigator wrapped in its
  /// scopes and back handling, then the app's `modalBuilder` presentation.
  Widget _flowPageChild(
    BuildContext context,
    KaiselActiveFlow<R> flow,
    GlobalKey<NavigatorState> flowNavigatorKey,
  ) {
    final flowNavigator = KaiselInnerNavigator<R>(
      router: flow.router,
      navigatorKey: flowNavigatorKey,
      pageBuilder: _effectiveSimpleBuilder,
      pageWrapper: pageWrapper,
    );

    final flowWithScopes = RouterScope<R>(
      router: flow.router,
      child: FlowScope(
        onComplete: (value) => router.completeFlow<Object>(value),
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (flow.router.canPop) {
              flow.router.pop();
            } else {
              router.completeFlow<Object>(null);
            }
          },
          child: Material(
            type: MaterialType.transparency,
            child: flowNavigator,
          ),
        ),
      ),
    );

    return modalBuilder!(context, flow.route, flowWithScopes);
  }

  List<Page<Object?>> _simpleMainPages(
    BuildContext context,
    List<KaiselStackEntry<R>> entries,
  ) {
    return [
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
                    _builder!(innerContext, entries[i].route),
              ),
            ),
            key: ValueKey<int>(entries[i].id),
            position: i,
            stackLength: entries.length,
            previous: i > 0 ? entries[i - 1].route : null,
          ),
        ),
    ];
  }

  List<Page<Object?>> _adaptiveMainPages(
    BuildContext context,
    List<KaiselStackEntry<R>> entries,
    KaiselAdaptivePageBuilder<R> builder,
  ) => buildAdaptivePages<R>(
    context: context,
    entries: entries,
    builder: builder,
    wrap: _wrapAdaptive,
    reportAbsorption: kDebugMode ? router.debugSetAbsorbedPositions : null,
    reportRenderedRoutes: (rendered) => _absorbedChangeReporter.report(
      stack: router.stack,
      rendered: rendered,
      observers: _mainObservers,
    ),
  );

  final _absorbedChangeReporter = KaiselAbsorbedChangeReporter();

  /// The simple builder used by the modal-flow inner navigator. When
  /// the delegate was constructed with an adaptive builder, synthesise
  /// one by calling the adaptive builder on a single-entry stack and
  /// using its widget. Modal flow screens are always rendered as
  /// standalone; `absorbing` is ignored on this path.
  KaiselPageBuilder<R> get _effectiveSimpleBuilder {
    final simple = _builder;
    if (simple != null) return simple;
    final adaptive = _adaptiveBuilder!;
    return (BuildContext context, R route) {
      final ctx = KaiselStackContext<R>(stack: [route], position: 0);
      return adaptive(context, route, ctx).widget;
    };
  }

  Page<Object?> _wrapSimple(KaiselPageWrapperContext<R> ctx) {
    final wrapper = pageWrapper;
    if (wrapper != null) return wrapper(ctx);
    return kaiselDefaultPage(
      ctx,
      transition: webTransition,
      androidPredictiveBack: androidPredictiveBack,
    );
  }

  Page<Object?> _wrapAdaptive(KaiselPageWrapperContext<R> ctx) {
    final wrapper = pageWrapper;
    if (wrapper != null) return wrapper(ctx);
    return kaiselDefaultPage(
      ctx,
      transition: webTransition,
      androidPredictiveBack: androidPredictiveBack,
    );
  }

  void _onDidRemovePage(Page<Object?> page) {
    // Navigator-driven pops sync our state, but guards do NOT rerun
    // on this path. That's by design.
    final key = page.key;
    if (key is _FlowPageKey) {
      // A flow page left the navigator. If the flow is still active, the
      // Navigator popped it imperatively (a raw Navigator.pop) — sync by
      // dismissing it with null. If it's already gone, completeFlow already
      // ran and this is just the declarative removal.
      if (key.flowIndex < router.activeFlows.length) router.dismissFlow();
      return;
    }
    final entryId = adaptiveEntryIdFromPageKey(key);
    if (entryId != null) {
      router.onPageRemoved(entryId);
    }
  }

  // DevTools inspection. Registration is gated on kDebugMode, so release
  // builds never touch the inspector.

  int? _inspectorToken;

  void _registerWithInspector() {
    if (kDebugMode) {
      _inspectorToken = KaiselInspector.instance.register(this);
    }
  }

  @override
  KaiselListenable get debugRevision => this;

  @override
  KaiselRootSnapshot debugSnapshot() {
    final branches = <KaiselShellSnapshot>[];
    final modules = <KaiselModuleSnapshot>[];
    for (final handle in _nested) {
      if (handle is BranchedShellRouter) {
        branches.add(_shellSnapshot(handle));
      } else if (handle.captureConfig() case final KaiselModuleConfig config) {
        modules.add(
          KaiselModuleSnapshot(
            routeType: _routeTypeOf(config.stack),
            stack: _routesStack(config.stack, const <int>{}),
          ),
        );
      }
    }
    // Encode + round-trip the current state through the codec once, sharing the
    // result between the `url` field and the codec problem.
    final codec = _codecState();
    return KaiselRootSnapshot(
      id: 'root-${identityHashCode(this).toRadixString(16)}',
      main: _entriesStack(
        router.depth,
        router.canPop,
        router.entries,
        router.debugAbsorbedPositions,
      ),
      branches: branches,
      modules: modules,
      flows: _flowSnapshots(),
      problems: _problems(codec.problem),
      guardTrace: _guardTraceSnapshot(),
      url: codec.url,
      history: <String>[
        for (final stack in router.debugHistory)
          stack.map((r) => '$r').join(' → '),
      ],
      origin: _originFrames(),
      replacesHistory: replacesHistoryEntry,
    );
  }

  // The app call site behind the most recent transition across the main
  // router, the shells, and their branches — the highest origin stamp wins.
  List<KaiselOriginFrame> _originFrames() {
    StackTrace? best;
    var bestSeq = 0;
    void consider(StackTrace? trace, int seq) {
      if (seq > bestSeq) {
        bestSeq = seq;
        best = trace;
      }
    }

    consider(router.debugLastTransitionOrigin, router.debugLastTransitionSeq);
    for (final handle in _nested) {
      if (handle is BranchedShellRouter) {
        consider(handle.debugLastSwitchOrigin, handle.debugLastSwitchSeq);
        for (final branch in handle.branches) {
          consider(
            branch.debugLastTransitionOrigin,
            branch.debugLastTransitionSeq,
          );
        }
      }
    }
    return kaiselOriginFrames(best);
  }

  List<KaiselProblemSnapshot> _problems(KaiselProblemSnapshot? codecProblem) {
    final out = <KaiselProblemSnapshot>[];
    void add(String where, KaiselNoOp? noOp) {
      if (noOp == null) return;
      out.add(
        KaiselProblemSnapshot(
          kind: 'noOp',
          router: where,
          detail:
              'A navigation landing on "${noOp.top}" changed nothing — the '
              'route is value-equal to the current top (often a missing '
              '`props` override).',
        ),
      );
    }

    add('main', router.debugLastNoOp);
    var shellIndex = 0;
    for (final handle in _nested) {
      if (handle is BranchedShellRouter) {
        for (var b = 0; b < handle.branchCount; b++) {
          final branch = handle.builtBranchAt(b);
          if (branch case final branch?) {
            add('shell$shellIndex.branch$b', branch.debugLastNoOp);
          }
        }
        shellIndex++;
      }
    }
    final flows = router.activeFlows;
    for (var i = 0; i < flows.length; i++) {
      add('flow:$i', flows[i].router.debugLastNoOp);
    }

    if (codecProblem case final problem?) out.add(problem);
    return out;
  }

  // Encodes the current configuration and round-trips it through the codec
  // once. Returns the encoded URL (null if no codec / encode threw) and a
  // codec problem when the state isn't deep-linkable.
  ({String? url, KaiselProblemSnapshot? problem}) _codecState() {
    final codec = _codec;
    if (codec == null) return (url: null, problem: null);
    final Uri uri;
    try {
      uri = codec.encode(currentConfiguration);
    } catch (e) {
      return (
        url: null,
        problem: KaiselProblemSnapshot(
          kind: 'codec',
          router: 'main',
          detail: 'The codec threw while encoding the current state: $e',
        ),
      );
    }
    bool roundTrips;
    try {
      roundTrips = codec.decode(uri) != null;
    } catch (_) {
      roundTrips = false;
    }
    return (
      url: uri.toString(),
      problem: roundTrips
          ? null
          : KaiselProblemSnapshot(
              kind: 'codec',
              router: 'main',
              detail:
                  'The current state encodes to "$uri", but that URL does not '
                  'decode back — the codec round-trip is broken (this state is '
                  'not deep-linkable).',
            ),
    );
  }

  @override
  List<String>? debugDecode(String url) {
    final codec = _codec;
    if (codec == null) return null;
    try {
      final config = codec.decode(Uri.parse(url));
      if (config == null) return null;
      final lines = <String>[
        'main: ${config.mainStack.map((r) => '$r').join(' → ')}',
      ];
      final nested = config.nestedState;
      if (nested case KaiselShellConfig(
        :final activeBranch,
        :final activeBranchStack,
      )) {
        lines.add(
          'shell: branch $activeBranch → '
          '${activeBranchStack.map((r) => '$r').join(' → ')}',
        );
      } else if (nested case KaiselModuleConfig(:final stack)) {
        lines.add('module: ${stack.map((r) => '$r').join(' → ')}');
      }
      return lines;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, Object?>> debugApplyCommand(
    Map<String, Object?> command,
  ) async {
    try {
      switch (command['cmd']) {
        case 'deepLink':
          final codec = _codec;
          if (codec == null) return _cmd(false, 'No codec wired.');
          final config = codec.decode(Uri.parse('${command['url'] ?? ''}'));
          if (config == null) return _cmd(false, 'URL did not decode.');
          await setNewRoutePath(config);
          return _cmd(true, 'Applied ${command['url']}.');
        case 'pop':
          final popped = await router.pop();
          return _cmd(popped, popped ? 'Popped.' : 'Nothing to pop.');
        case 'switchBranch':
          final shellIndex = (command['shell'] as num?)?.toInt() ?? 0;
          final branch = (command['branch'] as num?)?.toInt() ?? 0;
          final shells = _nested.whereType<BranchedShellRouter>().toList();
          if (shellIndex < 0 || shellIndex >= shells.length) {
            return _cmd(false, 'No shell $shellIndex.');
          }
          final shell = shells[shellIndex];
          if (branch < 0 || branch >= shell.branchCount) {
            return _cmd(false, 'No branch $branch.');
          }
          shell.switchTo(branch);
          return _cmd(true, 'Switched shell $shellIndex to branch $branch.');
        case 'dismissFlow':
          if (router.activeFlows.isEmpty) return _cmd(false, 'No active flow.');
          router.dismissFlow();
          return _cmd(true, 'Dismissed the active flow.');
        case 'timeTravel':
          final index = (command['index'] as num?)?.toInt() ?? -1;
          final history = router.debugHistory;
          if (index < 0 || index >= history.length) {
            return _cmd(false, 'No history entry $index.');
          }
          await router.set(history[index]);
          return _cmd(true, 'Restored history entry $index.');
        case _:
          return _cmd(false, 'Unknown command: ${command['cmd']}.');
      }
    } catch (e) {
      return _cmd(false, 'Command failed: $e');
    }
  }

  Map<String, Object?> _cmd(bool ok, String message) => <String, Object?>{
    'ok': ok,
    'message': message,
  };

  KaiselGuardTraceSnapshot? _guardTraceSnapshot() {
    final run = router.debugLastGuardRun;
    if (run == null) return null;
    return KaiselGuardTraceSnapshot(
      input: <String>[for (final route in run.input) route.toString()],
      steps: <KaiselGuardStepSnapshot>[
        for (final step in run.steps)
          KaiselGuardStepSnapshot(
            guard: step.label,
            input: <String>[for (final route in step.input) route.toString()],
            output: <String>[for (final route in step.output) route.toString()],
            changed: step.changed,
          ),
      ],
      output: <String>[for (final route in run.output) route.toString()],
    );
  }

  KaiselShellSnapshot _shellSnapshot(BranchedShellRouter shell) {
    return KaiselShellSnapshot(
      type: shell.runtimeType.toString(),
      activeBranch: shell.activeBranch,
      branchCount: shell.branchCount,
      // Walk every branch by real index. builtBranchAt never builds, so
      // inspecting a lazy shell doesn't materialise its dormant branches.
      branches: <KaiselBranchSnapshot>[
        for (var i = 0; i < shell.branchCount; i++)
          _branchSnapshot(i, shell.builtBranchAt(i)),
      ],
    );
  }

  KaiselBranchSnapshot _branchSnapshot(int index, KaiselNavigator? branch) {
    if (branch == null) {
      return KaiselBranchSnapshot(
        index: index,
        built: false,
        routeType: '—',
        stack: const KaiselStackSnapshot(
          depth: 0,
          canPop: false,
          entries: <KaiselEntrySnapshot>[],
        ),
      );
    }
    return KaiselBranchSnapshot(
      index: index,
      built: true,
      routeType: _routeTypeOf(branch.stack),
      stack: _routesStack(branch.stack, branch.debugAbsorbedPositions),
    );
  }

  List<KaiselFlowSnapshot> _flowSnapshots() {
    final flows = router.activeFlows;
    return <KaiselFlowSnapshot>[
      for (var i = 0; i < flows.length; i++)
        KaiselFlowSnapshot(
          depth: i,
          type: flows[i].route.runtimeType.toString(),
          stack: _entriesStack(
            flows[i].router.depth,
            flows[i].router.canPop,
            flows[i].router.entries,
            flows[i].router.debugAbsorbedPositions,
          ),
        ),
    ];
  }

  KaiselStackSnapshot _entriesStack<S extends KaiselRoute>(
    int depth,
    bool canPop,
    List<KaiselStackEntry<S>> entries,
    Set<int> absorbed,
  ) => KaiselStackSnapshot(
    depth: depth,
    canPop: canPop,
    entries: <KaiselEntrySnapshot>[
      for (var i = 0; i < entries.length; i++)
        _entrySnapshot(entries[i].id, entries[i].route, absorbed.contains(i)),
    ],
  );

  KaiselStackSnapshot _routesStack(
    List<KaiselRoute> routes,
    Set<int> absorbed,
  ) => KaiselStackSnapshot(
    depth: routes.length,
    canPop: routes.length > 1,
    entries: <KaiselEntrySnapshot>[
      for (var i = 0; i < routes.length; i++)
        _entrySnapshot(i, routes[i], absorbed.contains(i)),
    ],
  );

  KaiselEntrySnapshot _entrySnapshot(
    int id,
    KaiselRoute route,
    bool absorbed,
  ) => KaiselEntrySnapshot(
    id: id,
    type: route.runtimeType.toString(),
    props: <String>[for (final prop in route.props) '$prop'],
    label: route.toString(),
    absorbed: absorbed,
  );

  String _routeTypeOf(List<KaiselRoute> stack) =>
      stack.isEmpty ? 'unknown' : stack.first.runtimeType.toString();

  @override
  void dispose() {
    _isDisposed = true;
    final token = _inspectorToken;
    if (token case final t?) {
      KaiselInspector.instance.deregister(t);
    }
    router.removeListener(_onRootChanged);
    for (final handle in _nested) {
      final listener = _nestedListeners.remove(handle);
      if (listener != null) handle.removeListener(listener);
    }
    _nested.clear();
    _nestedListeners.clear();
    super.dispose();
  }
}

/// Inherited widget that exposes a [KaiselNestedHost] (the delegate) to
/// descendants. A mounted [KaiselBranchedShell] or [KaiselModuleMount]
/// looks this up to register itself for URL capture/restore.
///
/// Not exported from `package:kaisel/kaisel.dart` — typical apps don't
/// need to reference it.
class KaiselNestedHostScope extends InheritedWidget {
  /// Create a scope around [child] exposing [host].
  const KaiselNestedHostScope({
    super.key,
    required this.host,
    required super.child,
  });

  /// The host (typically the [KaiselRouterDelegate]).
  final KaiselNestedHost host;

  /// Look up the nearest host, or `null` if none is mounted (e.g.
  /// unit tests that mount a nested router outside a delegate).
  static KaiselNestedHost? maybeOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<KaiselNestedHostScope>();
    return scope?.host;
  }

  @override
  bool updateShouldNotify(KaiselNestedHostScope old) =>
      !identical(old.host, host);
}

/// Identity key for a modal flow's page, tagged so [_onDidRemovePage] can tell
/// a flow page apart from a main-stack entry page. Keyed by the flow's index in
/// `activeFlows`, which is stable for the flow's lifetime because flows
/// complete LIFO.
@immutable
class _FlowPageKey extends LocalKey {
  const _FlowPageKey(this.flowIndex);

  final int flowIndex;

  @override
  bool operator ==(Object other) =>
      other is _FlowPageKey && other.flowIndex == flowIndex;

  @override
  int get hashCode => Object.hash(_FlowPageKey, flowIndex);
}

/// A modal flow rendered as a transparent route on the main navigator. The
/// route is non-opaque so the main stack shows through; the app's
/// `modalBuilder` draws the scrim and the route barrier stays out of the way.
class _FlowPage extends Page<Object?> {
  const _FlowPage({
    required _FlowPageKey super.key,
    required this.child,
    super.name,
    super.arguments,
  });

  final Widget child;

  @override
  Route<Object?> createRoute(BuildContext context) {
    return PageRouteBuilder<Object?>(
      settings: this,
      opaque: false,
      barrierDismissible: false,
      maintainState: true,
      pageBuilder: (_, _, _) => child,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }
}
