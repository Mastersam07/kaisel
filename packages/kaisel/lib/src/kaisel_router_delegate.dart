import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:kaisel_core/framework.dart';

import 'kaisel_adaptive.dart';
import 'kaisel_branched_shell.dart';
import 'kaisel_inner_navigator.dart';
import 'kaisel_page_scope.dart';
import 'kaisel_page_wrapper.dart';
import 'kaisel_scope.dart';

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
/// The [flowChild] is already wired up to its own router; just wrap it
/// in whatever presentation you want.
typedef KaiselModalBuilder =
    Widget Function(
      BuildContext context,
      KaiselModalRoute<Object?> flowRoute,
      Widget flowChild,
    );

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
    KaiselConfigCodec<R>? codec,
  }) : _builder = builder,
       _adaptiveBuilder = null,
       _codec = codec {
    router.addListener(_safeNotifyListeners);
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
    KaiselConfigCodec<R>? codec,
  }) : _builder = null,
       _adaptiveBuilder = builder,
       _codec = codec {
    router.addListener(_safeNotifyListeners);
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

  /// Optional builder that renders an active modal flow over the main
  /// UI. Required if your app uses `router.run<T>(...)`.
  final KaiselModalBuilder? modalBuilder;

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
  KaiselNestedConfig? _pendingNested;
  bool _isDisposed = false;

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
  void unregisterNested(KaiselNestedHandle handle) {
    final index = _nested.indexWhere((h) => identical(h, handle));
    if (index < 0) return;
    _nested.removeAt(index);
    handle.removeListener(_safeNotifyListeners);
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
    final entries = router.entries;
    final mainPages = switch (_adaptiveBuilder) {
      final builder? => _adaptiveMainPages(context, entries, builder),
      _ => _simpleMainPages(context, entries),
    };

    _lastBuiltMainPageCount = mainPages.length;

    final mainNavigator = Navigator(
      key: navigatorKey,
      pages: mainPages,
      onDidRemovePage: _onDidRemovePage,
    );

    Widget content = mainNavigator;

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

    for (var i = 0; i < activeFlows.length; i++) {
      content = _buildFlowLayer(
        context: context,
        inner: content,
        flow: activeFlows[i],
        flowNavigatorKey: _flowNavigatorKeys[i],
      );
    }

    content = RouterScope<R>(router: router, child: content);
    // Install the host scope so descendant nested routers (branched
    // shells and module mounts) can register for URL capture/restore.
    return KaiselNestedHostScope(host: this, child: content);
  }

  Widget _buildFlowLayer({
    required BuildContext context,
    required Widget inner,
    required KaiselActiveFlow<R> flow,
    required GlobalKey<NavigatorState> flowNavigatorKey,
  }) {
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
          child: flowNavigator,
        ),
      ),
    );

    final flowUi = modalBuilder!(context, flow.route, flowWithScopes);
    return Stack(children: [inner, flowUi]);
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
  );

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
    return MaterialPage<Object?>(key: ctx.key, child: ctx.child);
  }

  Page<Object?> _wrapAdaptive(KaiselPageWrapperContext<R> ctx) {
    final wrapper = pageWrapper;
    if (wrapper != null) return wrapper(ctx);
    return MaterialPage<Object?>(key: ctx.key, child: ctx.child);
  }

  void _onDidRemovePage(Page<Object?> page) {
    // Navigator-driven pops sync our state, but guards do NOT rerun
    // on this path. That's by design.
    final entryId = adaptiveEntryIdFromPageKey(page.key);
    if (entryId != null) {
      router.onPageRemoved(entryId);
    }
  }

  // DevTools inspection. The delegate is the snapshot hub: it sees the main
  // router, the registered nested handles, and the active flows, and it
  // already notifies on all of them. Registration is gated on kDebugMode, so
  // release builds never touch the inspector and pay nothing.

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
            stack: _routesStack(config.stack),
          ),
        );
      }
    }
    return KaiselRootSnapshot(
      id: 'root-${identityHashCode(this).toRadixString(16)}',
      main: _entriesStack(router.depth, router.canPop, router.entries),
      branches: branches,
      modules: modules,
      flows: _flowSnapshots(),
      problems: _problems(),
      guardTrace: _guardTraceSnapshot(),
      url: _encodeUrl(),
    );
  }

  List<KaiselProblemSnapshot> _problems() {
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
        for (var b = 0; b < handle.branches.length; b++) {
          add('shell$shellIndex.branch$b', handle.branches[b].debugLastNoOp);
        }
        shellIndex++;
      }
    }
    final flows = router.activeFlows;
    for (var i = 0; i < flows.length; i++) {
      add('flow:$i', flows[i].router.debugLastNoOp);
    }

    // Codec round-trip: if a codec is wired, the current state should encode to
    // a URL that decodes back. A null decode (or a throw) means this state is
    // not URL-addressable — deep links to it would fail.
    final codec = _codec;
    if (codec case final c?) {
      final config = currentConfiguration;
      try {
        final uri = c.encode(config);
        if (c.decode(uri) == null) {
          out.add(
            KaiselProblemSnapshot(
              kind: 'codec',
              router: 'main',
              detail:
                  'The current state encodes to "$uri", but that URL does not '
                  'decode back — the codec round-trip is broken (this state is '
                  'not deep-linkable).',
            ),
          );
        }
      } catch (e) {
        out.add(
          KaiselProblemSnapshot(
            kind: 'codec',
            router: 'main',
            detail: 'The codec threw while encoding the current state: $e',
          ),
        );
      }
    }
    return out;
  }

  String? _encodeUrl() {
    final codec = _codec;
    if (codec == null) return null;
    try {
      return codec.encode(currentConfiguration).toString();
    } catch (_) {
      // A user codec may throw on a transient configuration; the URL is a
      // best-effort debug field, so swallow and report none.
      return null;
    }
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
    final branches = shell.branches;
    return KaiselShellSnapshot(
      type: shell.runtimeType.toString(),
      activeBranch: shell.activeBranch,
      branchCount: shell.branchCount,
      branches: <KaiselBranchSnapshot>[
        for (var i = 0; i < branches.length; i++)
          KaiselBranchSnapshot(
            index: i,
            routeType: _routeTypeOf(branches[i].stack),
            stack: _routesStack(branches[i].stack),
          ),
      ],
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
          ),
        ),
    ];
  }

  KaiselStackSnapshot _entriesStack<S extends KaiselRoute>(
    int depth,
    bool canPop,
    List<KaiselStackEntry<S>> entries,
  ) => KaiselStackSnapshot(
    depth: depth,
    canPop: canPop,
    entries: <KaiselEntrySnapshot>[
      for (final entry in entries) _entrySnapshot(entry.id, entry.route),
    ],
  );

  KaiselStackSnapshot _routesStack(List<KaiselRoute> routes) =>
      KaiselStackSnapshot(
        depth: routes.length,
        canPop: routes.length > 1,
        entries: <KaiselEntrySnapshot>[
          for (var i = 0; i < routes.length; i++) _entrySnapshot(i, routes[i]),
        ],
      );

  KaiselEntrySnapshot _entrySnapshot(int id, KaiselRoute route) =>
      KaiselEntrySnapshot(
        id: id,
        type: route.runtimeType.toString(),
        props: <String>[for (final prop in route.props) '$prop'],
        label: route.toString(),
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
    router.removeListener(_safeNotifyListeners);
    for (final handle in _nested) {
      handle.removeListener(_safeNotifyListeners);
    }
    _nested.clear();
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
