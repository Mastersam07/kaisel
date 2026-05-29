import 'dart:async';

import 'gate_route.dart';

/// A guard transforms a proposed navigation stack before it is applied.
///
/// Guards run in pipeline order; each receives the output of the
/// previous. Return the [proposed] stack unchanged to allow the
/// navigation, return a different stack to redirect, or return
/// [current] (or a copy) to refuse the change.
///
/// Guards can be synchronous or asynchronous — the return type is
/// `FutureOr<List<R>>`. When all guards in the pipeline are synchronous
/// the navigation completes synchronously; introducing one async guard
/// makes the whole pipeline async.
///
/// Guards close over whatever app state they need (an auth notifier,
/// feature flags, etc.). The router does not know about app state — it
/// just runs the pipeline.
///
/// Example:
///
/// ```dart
/// GateGuard<AppRoute> authGuard(ValueListenable<AuthState> auth) {
///   return (current, proposed) {
///     final needsAuth = proposed.any((r) => r is RequiresAuth);
///     if (needsAuth && !auth.value.isAuthenticated) {
///       return const [Login()];
///     }
///     return proposed;
///   };
/// }
///
/// final router = GateRouter<AppRoute>(
///   initial: const Home(),
///   guards: [authGuard(authNotifier)],
/// );
/// ```
typedef GateGuard<R extends GateRoute> = FutureOr<List<R>> Function(
  List<R> current,
  List<R> proposed,
);
