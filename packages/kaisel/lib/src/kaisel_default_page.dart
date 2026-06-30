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
/// out. On non-web platforms this is ignored — routes always use the native
/// [MaterialPage] transition.
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
  if (!isWeb || transition == KaiselWebTransition.platform) {
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
  Route<T> createRoute(BuildContext context) {
    final duration = fade ? const Duration(milliseconds: 150) : Duration.zero;
    return PageRouteBuilder<T>(
      settings: this,
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (_, _, _) => child,
      transitionsBuilder: fade
          ? (_, animation, _, child) =>
                FadeTransition(opacity: animation, child: child)
          : (_, _, _, child) => child,
    );
  }
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
