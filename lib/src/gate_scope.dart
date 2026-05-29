import 'package:flutter/widgets.dart';

import 'gate_route.dart';
import 'gate_router.dart';

/// Inherited widget that exposes the [GateRouter] in effect at a point
/// in the widget tree.
///
/// `RouterScope` is installed in three places:
///
/// - by the main [GateRouterDelegate], at the root of the app;
/// - by [GateShell] (v0.2), once per branch, with that branch's router;
/// - by [GateRouterDelegate] when rendering an active modal flow, with
///   the flow's sub-router.
///
/// Because lookups walk **up** the tree, the innermost scope wins. Use
/// `context.router<R>()` to get the router that should handle a
/// navigation request from the current widget — that resolves to the
/// branch router inside a shell, the flow router inside a flow, or the
/// main router elsewhere.
class RouterScope<R extends GateRoute> extends InheritedWidget {
  /// Create a scope around [child] exposing [router].
  const RouterScope({
    super.key,
    required this.router,
    required super.child,
  });

  /// The router in effect at this scope.
  final GateRouter<R> router;

  /// The nearest enclosing [RouterScope] of route type [R].
  ///
  /// Throws a [FlutterError] if none is found. Use [maybeOf] for
  /// optional lookup.
  static RouterScope<R> of<R extends GateRoute>(BuildContext context) {
    final scope = maybeOf<R>(context);
    if (scope == null) {
      throw FlutterError(
        'RouterScope<$R> not found in widget tree.\n'
        'Ensure your widget is inside a Router whose delegate is a '
        'GateRouterDelegate<$R>, or inside a GateShell<$R>.',
      );
    }
    return scope;
  }

  /// Like [of], but returns `null` if no scope is found.
  static RouterScope<R>? maybeOf<R extends GateRoute>(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RouterScope<R>>();

  @override
  bool updateShouldNotify(RouterScope<R> old) =>
      !identical(old.router, router);
}

/// Unified router accessors. `context.router<R>()` resolves to the
/// nearest enclosing [GateRouter] — the flow router if inside a modal
/// flow, the branch router if inside a shell, otherwise the main
/// router.
extension GateRouterContextX on BuildContext {
  /// The nearest enclosing router. Throws if none is found.
  GateRouter<R> router<R extends GateRoute>() => RouterScope.of<R>(this).router;

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

/// Inherited widget that marks a subtree as living inside an active
/// modal flow. Non-generic so descendants can look it up without
/// knowing the host router's route type.
///
/// Installed by [GateRouterDelegate] around the flow's UI. Look up via
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
