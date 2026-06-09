import 'package:flutter/widgets.dart';
import 'package:kaisel_core/kaisel_core.dart';

import 'kaisel_page_scope.dart';

/// Inherited widget that exposes the [KaiselRouter] in effect at a point
/// in the widget tree.
///
/// `RouterScope` is installed in three places:
///
/// - by the main [KaiselRouterDelegate], at the root of the app;
/// - by [KaiselShell], once per branch, with that branch's router;
/// - by [KaiselRouterDelegate] when rendering an active modal flow, with
///   the flow's sub-router.
///
/// Because lookups walk **up** the tree, the innermost scope wins. Use
/// `context.router<R>()` to get the router that should handle a
/// navigation request from the current widget — that resolves to the
/// branch router inside a shell, the flow router inside a flow, or the
/// main router elsewhere.
class RouterScope<R extends KaiselRoute> extends InheritedWidget {
  /// Create a scope around [child] exposing [router].
  const RouterScope({super.key, required this.router, required super.child});

  /// The router in effect at this scope.
  final KaiselRouter<R> router;

  /// Whether this scope's router can take [route] — i.e. `route is R`.
  ///
  /// Works through a non-generic view because Dart reifies `R`: even when
  /// this scope is held as `RouterScope<KaiselRoute>`, the check runs against
  /// the instance's real route type.
  bool accepts(KaiselRoute route) => route is R;

  /// Type-erased navigation used by the `context.*` helpers, which select the
  /// target scope via [accepts] first, so each cast to `R` is sound.
  Future<void> pushRoute(KaiselRoute route) => router.push(route as R);

  /// Type-erased [KaiselRouter.replaceTop]; see [pushRoute].
  Future<void> replaceTopRoute(KaiselRoute route) =>
      router.replaceTop(route as R);

  /// Type-erased [KaiselRouter.pushOrReplaceTop]; see [pushRoute].
  Future<void> pushOrReplaceTopRoute(KaiselRoute route) =>
      router.pushOrReplaceTop(route as R);

  /// Type-erased [KaiselRouter.set]; see [pushRoute].
  Future<void> setRoutes(List<KaiselRoute> routes) =>
      router.set(routes.cast<R>());

  /// Run a modal [flow] on this scope's router; see [pushRoute].
  Future<T?> runFlow<T>(KaiselModalRoute<T> flow) => router.run<T>(flow);

  /// The nearest enclosing [RouterScope] of route type [R].
  ///
  /// Throws a [FlutterError] if none is found. Use [maybeOf] for
  /// optional lookup.
  static RouterScope<R> of<R extends KaiselRoute>(BuildContext context) {
    final scope = maybeOf<R>(context);
    if (scope == null) {
      if (ShellChromeScope.maybeOf(context) != null) {
        throw FlutterError(
          'RouterScope<$R> not found above this context.\n'
          'You are inside a shell chromeBuilder, where each branch installs '
          'its RouterScope BELOW the chrome — so context.router<$R>() cannot '
          'resolve a branch router from here.\n'
          'Use context.shell() to drive the shell (or the activeBranch / '
          'switchBranch arguments), or context.router() with your app root '
          'route type for the main router.',
        );
      }
      throw FlutterError(
        'RouterScope<$R> not found above this context.\n'
        'context.router<$R>() walks up the tree for the nearest '
        'RouterScope<$R>, installed at the app root, inside shell branch '
        'screens, and inside modal flows. Ensure this widget is mounted under '
        'a KaiselRouterDelegate<$R> (or the appropriate branch / flow).',
      );
    }
    return scope;
  }

  /// Like [of], but returns `null` if no scope is found.
  static RouterScope<R>? maybeOf<R extends KaiselRoute>(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RouterScope<R>>();

  @override
  bool updateShouldNotify(RouterScope<R> old) => !identical(old.router, router);
}

/// Marks the chrome subtree of a shell — the `chromeBuilder` output of
/// `KaiselShell` / `KaiselBranchedShell`.
///
/// Each branch installs its [RouterScope] *below* the chrome, so a
/// `context.router<R>()` call from the chrome can't resolve a branch router.
/// This marker lets [RouterScope.of] detect that case and point at
/// `context.shell()` instead of a generic "not found".
class ShellChromeScope extends InheritedWidget {
  /// Create a chrome marker around [child].
  const ShellChromeScope({super.key, required super.child});

  /// The nearest enclosing chrome marker, or `null`. Uses a non-dependent
  /// lookup — it is only consulted while composing an error message.
  static ShellChromeScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellChromeScope>();

  @override
  bool updateShouldNotify(ShellChromeScope old) => false;
}

/// Unified router accessors. `context.router<R>()` resolves to the
/// nearest enclosing [KaiselRouter] — the flow router if inside a modal
/// flow, the branch router if inside a shell, otherwise the main
/// router.
extension KaiselRouterContextX on BuildContext {
  /// The nearest enclosing router. Throws if none is found.
  KaiselRouter<R> router<R extends KaiselRoute>() =>
      RouterScope.of<R>(this).router;

  /// Resolve the active modal flow (the nearest one up the tree) with
  /// [value].
  ///
  /// The type parameter is for caller clarity — `completeFlow<bool>(true)`
  /// — but the runtime cast happens at the awaiting `router.run<T>(...)`
  /// boundary.
  ///
  /// Throws [FlutterError] if no [FlowScope] is found in the tree
  /// (i.e. you're not inside a modal flow).
  void completeFlow<T>(T? value) => FlowScope.of(this)._complete(value);

  /// Dismiss the active modal flow with `null`.
  void dismissFlow() => FlowScope.of(this)._complete(null);
}

/// Terse, go_router-style navigation on `BuildContext`.
///
/// Each verb resolves the target router by walking up the tree for the nearest
/// [RouterScope] whose route type the argument belongs to ([RouterScope.accepts]),
/// then forwards. So `context.push(const ProductDetail('42'))` finds the router
/// for the `ProductDetail` family without you naming it. The argument stays a
/// typed route, so you keep autocomplete and refactors; what you trade vs.
/// `context.router<R>().push(...)` is the *compile-time* check that the route
/// belongs to that router — here a wrong-family route throws at runtime instead.
/// Reach for `context.router<R>()` when you want that check back.
///
/// The lookup uses [BuildContext.visitAncestorElements] (no dependency is
/// created) because these are actions, not build-time reads.
extension KaiselContextNavigation on BuildContext {
  /// Push [route] onto the nearest router that accepts it.
  Future<void> push(KaiselRoute route) =>
      _scopeForRoute(route).pushRoute(route);

  /// Pop the nearest kaisel router. Returns `false` if it was already at root.
  ///
  /// When called from inside an overlay you pushed imperatively
  /// ([showModalBottomSheet], [showDialog], …), that overlay is closed instead
  /// — it isn't on the kaisel stack, and closing it is almost always what `pop`
  /// means there. To pop the typed route from inside an overlay, call `pop()` on
  /// a [KaiselRouter] directly (e.g. `context.router<R>().pop()`).
  Future<bool> pop() {
    Widget? boundary;
    visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is KaiselPageScope || widget is RouterScope) {
        boundary = widget;
        return false;
      }
      return true;
    });
    return switch (Navigator.maybeOf(this)) {
      final navigator? when boundary is RouterScope && navigator.canPop() =>
        navigator.maybePop(),
      _ => _nearestRouterScope().router.pop(),
    };
  }

  /// Replace the top of the nearest router that accepts [route].
  Future<void> replaceTop(KaiselRoute route) =>
      _scopeForRoute(route).replaceTopRoute(route);

  /// Push, or replace the top if it's the same type, on the nearest accepting
  /// router.
  Future<void> pushOrReplaceTop(KaiselRoute route) =>
      _scopeForRoute(route).pushOrReplaceTopRoute(route);

  /// Replace the whole stack of the nearest router that accepts the routes.
  Future<void> set(List<KaiselRoute> routes) =>
      _scopeForRoute(routes.first).setRoutes(routes);

  /// Open [flow] as a modal on the nearest router that accepts it, awaiting
  /// its typed result.
  Future<T?> run<T>(KaiselModalRoute<T> flow) =>
      _scopeForRoute(flow).runFlow<T>(flow);

  /// The nearest [RouterScope] whose router accepts [route]. Throws a
  /// [FlutterError] if none does.
  RouterScope _scopeForRoute(KaiselRoute route) {
    RouterScope? found;
    visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is RouterScope && widget.accepts(route)) {
        found = widget;
        return false;
      }
      return true;
    });
    switch (found) {
      case final scope?:
        return scope;
      case _:
        throw FlutterError(
          'No KaiselRouter above this context accepts a ${route.runtimeType}.\n'
          'context.push / replaceTop / pushOrReplaceTop resolve the nearest '
          'router whose route type the argument belongs to. Ensure this widget '
          'is under a KaiselRouterDelegate (or branch / flow) whose route type '
          'is a supertype of ${route.runtimeType}.',
        );
    }
  }

  /// The nearest [RouterScope] regardless of route type. Throws if none.
  RouterScope _nearestRouterScope() {
    RouterScope? found;
    visitAncestorElements((element) {
      if (element.widget is RouterScope) {
        found = element.widget as RouterScope;
        return false;
      }
      return true;
    });
    switch (found) {
      case final scope?:
        return scope;
      case _:
        throw FlutterError(
          'No KaiselRouter found above this context for context.pop().',
        );
    }
  }
}

/// The common control surface of a kaisel shell. Both `KaiselBranchedShell`
/// (via `BranchedShellRouter`) and `KaiselShell` (via `ShellRouter`) expose it,
/// so descendants can switch tabs and read the active branch through one
/// accessor — `context.shell()` — without knowing which shell flavour is above
/// them, or its route type.
abstract interface class KaiselShellController implements Listenable {
  /// Index of the currently selected branch.
  int get activeBranch;

  /// Number of branches in the shell.
  int get branchCount;

  /// The active branch's router, type-erased. Lets shell chrome read the
  /// active stack (e.g. for a breadcrumb) and pop it, without holding a
  /// reference to the per-branch router. The controller notifies on both
  /// branch switches and active-stack changes.
  KaiselNavigator get current;

  /// Select a different branch. No-op if [branch] is already active.
  void switchTo(int branch);
}

/// Inherited widget exposing the nearest [KaiselShellController]. Installed by
/// `KaiselBranchedShell` and `KaiselShell`; reached via `context.shell()`.
class KaiselShellScope extends InheritedWidget {
  /// Create a scope around [child] exposing [controller].
  const KaiselShellScope({
    super.key,
    required this.controller,
    required super.child,
  });

  /// The shell controller in effect at this scope.
  final KaiselShellController controller;

  /// The nearest enclosing controller, or `null`.
  static KaiselShellController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<KaiselShellScope>()
      ?.controller;

  @override
  bool updateShouldNotify(KaiselShellScope old) =>
      !identical(old.controller, controller);
}

/// One accessor for switching tabs from anywhere inside any shell.
extension KaiselShellContextX on BuildContext {
  /// The nearest [KaiselShellController] — branched or homogeneous. Throws a
  /// [FlutterError] if there's no shell above this context.
  KaiselShellController shell() {
    final controller = KaiselShellScope.maybeOf(this);
    switch (controller) {
      case final controller?:
        return controller;
      case _:
        throw FlutterError(
          'context.shell() found no KaiselShell / KaiselBranchedShell above '
          'this context.',
        );
    }
  }
}

/// Inherited widget that marks a subtree as living inside an active
/// modal flow. Non-generic so descendants can look it up without
/// knowing the host router's route type.
///
/// Installed by [KaiselRouterDelegate] around the flow's UI. Look up via
/// `context.completeFlow()` rather than touching this directly.
class FlowScope extends InheritedWidget {
  /// Create a scope around [child] that closes over the host router's
  /// completion callback.
  const FlowScope({
    super.key,
    required void Function(Object? value) onComplete,
    required super.child,
  }) : _complete = onComplete;

  final void Function(Object? value) _complete;

  /// The nearest enclosing [FlowScope]. Throws if none is found.
  static FlowScope of(BuildContext context) {
    final scope = maybeOf(context);
    if (scope == null) {
      throw FlutterError(
        'FlowScope not found — completeFlow/dismissFlow can only be '
        'called from inside a modal flow started via router.run<T>(...).',
      );
    }
    return scope;
  }

  /// Like [of], but returns `null` if no scope is found.
  static FlowScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FlowScope>();

  @override
  bool updateShouldNotify(FlowScope old) => old._complete != _complete;
}
