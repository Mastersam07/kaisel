import 'package:flutter/widgets.dart';
import 'package:kaisel_core/kaisel_core.dart';

import 'kaisel_browser_history.dart';
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

  /// Type-erased [KaiselRouter.pushForResult]; see [pushRoute].
  Future<T?> pushRouteForResult<T>(KaiselRoute route) =>
      router.pushForResult<T>(route as R);

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

  /// Push [route] onto the nearest router that accepts it and await a typed
  /// result, delivered when that screen pops (see [pop]).
  ///
  /// The screen lives on the main stack — a normal route in the same
  /// [Navigator] — so root-navigator dialogs, shared observers, and ordinary
  /// navigation behave as usual. Use this instead of [run] when a screen
  /// needs to return a value without being lifted into a modal flow's
  /// separate navigator. See [KaiselRouter.pushForResult].
  Future<T?> pushForResult<T>(KaiselRoute route) =>
      _scopeForRoute(route).pushRouteForResult<T>(route);

  /// Pop the nearest kaisel router, optionally returning [result] to a
  /// matching [pushForResult] awaiter. Returns `false` if it was already at
  /// root.
  ///
  /// When called from inside an overlay you pushed imperatively
  /// ([showModalBottomSheet], [showDialog], …), that overlay is closed instead
  /// — it isn't on the kaisel stack, and closing it is almost always what `pop`
  /// means there. To pop the typed route from inside an overlay, call `pop()` on
  /// a [KaiselRouter] directly (e.g. `context.router<R>().pop()`).
  Future<bool> pop([Object? result]) {
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
      // Closing an imperative overlay (dialog/sheet): the result belongs to
      // that overlay's route, not the kaisel screen beneath it.
      final navigator? when boundary is RouterScope && navigator.canPop() =>
        navigator.maybePop(result),
      _ => _nearestRouterScope().router.pop(result),
    };
  }

  /// Pop the way the system back button does: ask the [Navigator] first, and
  /// only fall through to the kaisel stack when it has nothing to pop.
  ///
  /// Reach for this instead of [pop] whenever something *other than a route*
  /// may be dismissible — the difference is what gets consulted:
  ///
  /// - **Local history entries.** Widgets that dismiss without being routes
  ///   (a [Drawer], a [PopupMenuButton]) register a [LocalHistoryEntry] on
  ///   the enclosing route. `maybePop` closes those first; [pop] would leave
  ///   one open and remove the screen underneath it.
  /// - **[PopScope] vetoes.** A `canPop: false` scope stops the pop and gets
  ///   its `onPopInvokedWithResult` callback, so "intercept and redirect"
  ///   handlers still run. [pop] mutates the stack without asking.
  ///
  /// Returns whether the request was *handled* — popped, dismissed, or
  /// intercepted by a veto — matching [NavigatorState.maybePop]. A `false`
  /// means nothing claimed it and the back gesture should bubble to the OS.
  ///
  /// When the [Navigator] has nothing to pop the kaisel router is popped
  /// instead, so an adaptive layout that collapses several stack entries into
  /// one visible page still unwinds.
  Future<bool> maybePop([Object? result]) async {
    final navigator = Navigator.maybeOf(this);
    if (navigator == null) return _nearestRouterScope().router.pop(result);
    if (navigator.canPop()) return navigator.maybePop(result);
    return _nearestRouterScope().router.pop(result);
  }

  /// Go back one step, history-aligned, so the browser's own Back/Forward
  /// buttons keep mirroring the app stack — even across several pops in a row.
  ///
  /// On the web this moves the browser history *pointer* (a true Back) rather
  /// than rewriting the current entry: the resulting URL change restores the
  /// stack through your codec — the same inbound path the browser Back button
  /// uses — so the screen you leave becomes a *forward* entry instead of a
  /// lingering duplicate. Reach for this (instead of [pop]) when you want the
  /// browser history to track the app stack across multi-level back navigation.
  ///
  /// Falls back to [pop] when there is no browser history to traverse — off the
  /// web, on a cold deep link (no app entry behind the current one), or without
  /// a URL codec. Returns whether anything was navigated.
  ///
  /// Unlike [pop], it does not deliver a `pushForResult` value; the stack is
  /// restored from the URL, so use [pop] when a screen must return a result.
  Future<bool> back() => historyGo(-1);

  /// Like [back] but moves [delta] history entries — negative goes back,
  /// positive forward (forward is web-only). See [back] for the
  /// web-vs-fallback behavior.
  Future<bool> historyGo(int delta) async {
    final history = KaiselBrowserHistory.instance;
    if (history.isWeb) {
      // Going back: only if there are that many app entries behind us, else we
      // would step out of the app (e.g. a cold deep link). Forward is
      // best-effort — the browser ignores it past the end of history.
      if (delta < 0 && history.depth >= -delta) {
        history.go(delta);
        return true;
      }
      if (delta > 0) {
        history.go(delta);
        return true;
      }
    }
    // Fallback: pop |delta| times, clamped at the root. Forward has no
    // off-web meaning.
    if (delta >= 0) {
      return false;
    }
    var moved = false;
    for (var i = 0; i < -delta; i++) {
      if (!await pop()) {
        break;
      }
      moved = true;
    }
    return moved;
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
