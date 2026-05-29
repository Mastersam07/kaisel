import 'package:flutter/material.dart';

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
/// `context.router<R>()` resolves correctly anywhere in the app.
class GateRouterDelegate<R extends GateRoute> extends RouterDelegate<List<R>>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<List<R>> {
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

  @override
  List<R> get currentConfiguration => router.stack;

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

    return RouterScope<R>(router: router, child: content);
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
    // Navigator pages can be removed for two reasons:
    //   1. The user (system back, in-app pop button) initiated the pop.
    //      In this case the entry is still in our state; we sync it.
    //   2. We initiated the removal by mutating the router state, and
    //      Navigator is just animating out a page that's no longer in
    //      our pages list. The entry is already gone; onPageRemoved
    //      no-ops on unknown ids.
    //
    // Guards do NOT run on this path — by the time we hear from the
    // navigator, the pop has already animated. State-driven redirects
    // (auth, etc.) should listen to your app state and call router.set
    // or router.replace, not be implemented as pop-time guards.
    final key = page.key;
    if (key is! ValueKey<int>) return;
    router.onPageRemoved(key.value);
  }

  @override
  Future<void> setNewRoutePath(List<R> configuration) {
    if (configuration.isEmpty) return Future<void>.value();
    return router.applyFromInformation(configuration);
  }

  // popRoute is supplied by PopNavigatorRouterDelegateMixin. The default
  // calls navigatorKey.currentState?.maybePop(), which runs route-level
  // willPop hooks and ultimately fires onDidRemovePage, which syncs the
  // router state. Don't override it to "fall back" to router.pop() — a
  // false return from maybePop means the route declined to pop (or there
  // is no nav state), and we should respect that, not force-pop.

  @override
  void dispose() {
    router.removeListener(notifyListeners);
    super.dispose();
  }
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

    // The flow's UI sits inside two scopes: RouterScope (so
    // context.router<R>() resolves to the flow's sub-router) and
    // FlowScope (so context.completeFlow / context.dismissFlow find a
    // way to resolve the awaiter on the host router).
    final flowWithScopes = RouterScope<R>(
      router: flowRouter,
      child: FlowScope(
        onComplete: onComplete,
        child: PopScope(
          // canPop=false at the flow root means we handle the back —
          // we want flow-root back to dismiss the flow, not pop the
          // shell/main router underneath.
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
