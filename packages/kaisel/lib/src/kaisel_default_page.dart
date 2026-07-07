import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:kaisel_core/kaisel_core.dart';

import 'kaisel_page_wrapper.dart';

/// How kaisel's default page wrapper animates a route on the **web**.
///
/// On the web, Flutter derives `MaterialPage`'s transition from the host OS
/// (a Cupertino slide on Apple platforms, a zoom/fade elsewhere), which often
/// feels out of place in a browser. kaisel defaults to a quick [fade] instead;
/// pass another value to [KaiselRouterConfig] / [KaiselRouterDelegate] to opt
/// out. On non-web platforms this is ignored — routes use the native
/// [MaterialPage] transition, driven through Flutter's predictive-back builder
/// on Android so a nested-navigator route follows the OS back gesture.
///
/// Only the *default* wrapper honours this; a custom `pageWrapper` controls its
/// own transitions.
enum KaiselWebTransition {
  /// A quick cross-fade. The default.
  fade,

  /// No animation; the page appears instantly.
  none,

  /// The platform's native [MaterialPage] transition (Flutter's default).
  platform,
}

/// The page the default wrapper builds for [ctx], honouring [transition] on the
/// web and falling back to a native [MaterialPage] elsewhere.
///
/// [isWeb] defaults to [kIsWeb]; it is a parameter so the branching is testable
/// off the web.
Page<Object?> kaiselDefaultPage<R extends KaiselRoute>(
  KaiselPageWrapperContext<R> ctx, {
  required KaiselWebTransition transition,
  bool isWeb = kIsWeb,
}) {
  if (isWeb) {
    if (transition == KaiselWebTransition.platform) {
      return MaterialPage<Object?>(
        key: ctx.key,
        name: ctx.route.routeName,
        arguments: ctx.route,
        restorationId: ctx.route.restorationId,
        child: ctx.child,
      );
    }
    return _WebTransitionPage<Object?>(
      key: ctx.key,
      name: ctx.route.routeName,
      arguments: ctx.route,
      restorationId: ctx.route.restorationId,
      fade: transition == KaiselWebTransition.fade,
      child: ctx.child,
    );
  }
  return _KaiselMaterialPage<Object?>(
    key: ctx.key,
    name: ctx.route.routeName,
    arguments: ctx.route,
    restorationId: ctx.route.restorationId,
    child: ctx.child,
  );
}

class _KaiselMaterialPage<T> extends MaterialPage<T> {
  const _KaiselMaterialPage({
    required super.child,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  @override
  Route<T> createRoute(BuildContext context) => _KaiselPageRoute<T>(page: this);
}

class _KaiselPageRoute<T> extends PageRoute<T>
    with MaterialRouteTransitionMixin<T> {
  _KaiselPageRoute({required MaterialPage<T> page}) : super(settings: page);

  MaterialPage<T> get _page => settings as MaterialPage<T>;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  bool get maintainState => _page.maintainState;

  @override
  bool get fullscreenDialog => _page.fullscreenDialog;

  @override
  String get debugLabel => '${super.debugLabel}(${_page.name})';

  static const _predictive = PredictiveBackPageTransitionsBuilder();

  // Android predictive-back transition. On a nested navigator the enclosing
  // route's PopScope makes it decline the gesture (popGestureEnabled is false
  // when it would not pop), so only this innermost route animates — not twice.
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (Theme.of(context).platform == TargetPlatform.android) {
      return _predictive.buildTransitions<T>(
        this,
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    return super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}

class _WebTransitionPage<T> extends Page<T> {
  const _WebTransitionPage({
    required this.child,
    required this.fade,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  final Widget child;

  final bool fade;

  @override
  Route<T> createRoute(BuildContext context) => _WebTransitionRoute<T>(this);
}

// A [PageRoute], not a [PageRouteBuilder]: the builder captures its child, so a
// same-key page update (an adaptive master-detail swap keeps the key stable)
// would keep the stale child. Reading from `settings` rebuilds it, like
// [MaterialPage].
class _WebTransitionRoute<T> extends PageRoute<T> {
  _WebTransitionRoute(_WebTransitionPage<T> page) : super(settings: page);

  _WebTransitionPage<T> get _page => settings as _WebTransitionPage<T>;

  @override
  Duration get transitionDuration =>
      _page.fade ? const Duration(milliseconds: 150) : Duration.zero;

  @override
  Duration get reverseTransitionDuration => transitionDuration;

  @override
  bool get opaque => true;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _page.child;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _page.fade ? FadeTransition(opacity: animation, child: child) : child;
}

/// Carries the app's [KaiselWebTransition] down the tree so nested navigators
/// (shell branches, modules) apply the same default as the main stack. Installed
/// by [KaiselRouterDelegate]; you don't use it directly.
class KaiselWebTransitionScope extends InheritedWidget {
  /// Create the scope with the active [transition].
  const KaiselWebTransitionScope({
    super.key,
    required this.transition,
    required super.child,
  });

  /// The default web transition in effect below this scope.
  final KaiselWebTransition transition;

  /// The nearest transition, or [KaiselWebTransition.fade] if none is installed.
  static KaiselWebTransition of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<KaiselWebTransitionScope>()
          ?.transition ??
      KaiselWebTransition.fade;

  @override
  bool updateShouldNotify(KaiselWebTransitionScope oldWidget) =>
      oldWidget.transition != transition;
}
