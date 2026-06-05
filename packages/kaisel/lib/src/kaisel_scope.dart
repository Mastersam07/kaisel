import 'package:flutter/widgets.dart';
import 'package:kaisel_core/kaisel_core.dart';

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

  /// The nearest enclosing [RouterScope] of route type [R].
  ///
  /// Throws a [FlutterError] if none is found. Use [maybeOf] for
  /// optional lookup.
  static RouterScope<R> of<R extends KaiselRoute>(BuildContext context) {
    final scope = maybeOf<R>(context);
    if (scope == null) {
      final chrome = ShellChromeScope.maybeOf(context);
      switch (chrome) {
        case final chrome?:
          throw FlutterError(
            'RouterScope<$R> not found above this context.\n'
            'You are inside a shell chromeBuilder, where each branch installs '
            'its RouterScope BELOW the chrome — so context.router<$R>() cannot '
            'resolve a branch router from here.\n'
            'Use ${chrome.accessorHint} to drive the shell (or the activeBranch '
            '/ switchBranch arguments), or context.router() with your app root '
            'route type for the main router.',
          );
        case _:
          throw FlutterError(
            'RouterScope<$R> not found above this context.\n'
            'context.router<$R>() walks up the tree for the nearest '
            'RouterScope<$R>, installed at the app root, inside shell branch '
            'screens, and inside modal flows. Ensure this widget is mounted under '
            'a KaiselRouterDelegate<$R> (or the appropriate branch / flow).',
          );
      }
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
/// This marker lets [RouterScope.of] detect that case and point at the shell's
/// own accessor ([accessorHint]) instead of a generic "not found".
class ShellChromeScope extends InheritedWidget {
  /// Create a chrome marker around [child] advertising [accessorHint].
  const ShellChromeScope({
    super.key,
    required this.accessorHint,
    required super.child,
  });

  /// The accessor to suggest in the error — e.g. `context.branchedShell()`
  /// or `context.shellRouter<R>()`.
  final String accessorHint;

  /// The nearest enclosing chrome marker, or `null`. Uses a non-dependent
  /// lookup — it is only consulted while composing an error message.
  static ShellChromeScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellChromeScope>();

  @override
  bool updateShouldNotify(ShellChromeScope old) =>
      old.accessorHint != accessorHint;
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
