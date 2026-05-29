import 'package:flutter/material.dart';

import 'gate_route.dart';
import 'gate_router.dart';

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

/// The renderer over a [GateRouter].
///
/// Listens to the router for changes and rebuilds a [Navigator] with
/// the current stack of pages. Hands system back-button events back to
/// the router so it can sync state.
class GateRouterDelegate<R extends GateRoute>
    extends RouterDelegate<List<R>>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<List<R>> {
  /// Create a delegate driving [router].
  ///
  /// [builder] resolves a route to a widget — use pattern matching here
  /// so the compiler enforces exhaustiveness over your sealed type.
  ///
  /// [pageWrapper] optionally customises how the widget becomes a
  /// [Page]; defaults to a [MaterialPage].
  GateRouterDelegate({
    required this.router,
    required this.builder,
    this.pageWrapper,
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

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  List<R> get currentConfiguration => router.stack;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      pages: [
        for (final entry in router.entries)
          _wrap(context, entry.route, ValueKey<int>(entry.id)),
      ],
      onDidRemovePage: _onDidRemovePage,
    );
  }

  Page<Object?> _wrap(BuildContext context, R route, LocalKey key) {
    final child = builder(context, route);
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
