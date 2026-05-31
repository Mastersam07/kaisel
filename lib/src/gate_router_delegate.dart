import 'package:flutter/material.dart';

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
/// [GateShellHostScope] so a mounted [GateBranchedShell] can register
/// itself for URL capture/restore.
///
/// In v0.5 the configuration type became [GateConfig], so URLs can
/// describe state inside a branched shell. Stack-only callers should
/// keep using [GateStackCodec] and wire it via
/// `GateRouteInformationParser.fromStackCodec` — no other migration
/// is needed.
class GateRouterDelegate<R extends GateRoute>
    extends RouterDelegate<GateConfig<R>>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<GateConfig<R>>
    implements GateShellHost {
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
    router.addListener(notifyListeners);
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
  // A mounted GateBranchedShell registers itself as the URL-addressable
  // shell. If a URL with shell state arrives before any shell mounts
  // (cold start at a deep link), the state is queued in _pendingShell
  // and applied when the shell registers.

  GateShellRestoreHandle? _shell;
  GateShellConfig? _pendingShell;

  @override
  void registerShell(GateShellRestoreHandle shell) {
    if (identical(_shell, shell)) return;
    _shell?.removeListener(notifyListeners);
    _shell = shell;
    // Forward branch / activeBranch changes to ourselves so the URL
    // updates as the user navigates inside the shell.
    shell.addListener(notifyListeners);
    final pending = _pendingShell;
    if (pending != null) {
      _pendingShell = null;
      // Fire-and-forget — guards in branch routers handle errors;
      // surfacing a Future here would force every callsite to be
      // async.
      shell.restoreFromConfig(pending);
    }
    // A newly-registered shell may already have non-default state
    // (e.g. apps that pre-seed branch stacks). Notify so the URL bar
    // reflects it.
    notifyListeners();
  }

  @override
  void unregisterShell(GateShellRestoreHandle shell) {
    if (!identical(_shell, shell)) return;
    _shell!.removeListener(notifyListeners);
    _shell = null;
    notifyListeners();
  }

  @override
  GateConfig<R> get currentConfiguration => GateConfig<R>(
        mainStack: router.stack,
        shellState: _shell?.captureConfig(),
      );

  @override
  Future<void> setNewRoutePath(GateConfig<R> configuration) async {
    if (configuration.mainStack.isEmpty) return;
    await router.applyFromInformation(configuration.mainStack);
    final shellState = configuration.shellState;
    if (shellState == null) return;
    final shell = _shell;
    if (shell case final shell?) {
      await shell.restoreFromConfig(shellState);
    } else {
      _pendingShell = shellState;
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
    // Install the shell-host scope so a descendant GateBranchedShell
    // can register itself for URL capture/restore.
    return GateShellHostScope(host: this, child: content);
  }

  Page<Object?> _wrap(BuildContext context, R route, LocalKey key) {
    final child = Builder(
      builder: (innerContext) => builder(innerContext, route),
    );
    final wrapper = pageWrapper;
    if (wrapper != null) {
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
    router.removeListener(notifyListeners);
    _shell?.removeListener(notifyListeners);
    super.dispose();
  }
}

/// Inherited widget that exposes a [GateShellHost] (the delegate) to
/// descendants. A mounted [GateBranchedShell] looks this up to register
/// itself for URL capture/restore.
///
/// Not exported from `package:gate/gate.dart` — typical apps don't
/// need to reference it.
class GateShellHostScope extends InheritedWidget {
  /// Create a scope around [child] exposing [host].
  const GateShellHostScope({
    super.key,
    required this.host,
    required super.child,
  });

  /// The host (typically the [GateRouterDelegate]).
  final GateShellHost host;

  /// Look up the nearest host, or `null` if none is mounted (e.g. unit
  /// tests that mount a shell outside a delegate).
  static GateShellHost? maybeOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<GateShellHostScope>();
    return scope?.host;
  }

  @override
  bool updateShouldNotify(GateShellHostScope old) => !identical(old.host, host);
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
