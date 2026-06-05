// Demonstrations of `unused_guard_redirect`.
//
// A guard that returns the proposed stack unchanged on every path is a no-op.
// The rule fires only when the body is purely returns and control flow, so a
// guard kept for a side effect (logging) is left alone.

// Guards are normally written inline in a `guards: [...]` list; they're bound
// to names here only so the demo can label them.
// ignore_for_file: unused_element, avoid_print
// ignore_for_file: prefer_function_declarations_over_variables

import 'package:kaisel/kaisel.dart';

sealed class _AppRoute extends KaiselRoute {
  const _AppRoute();
}

final class _Home extends _AppRoute {
  const _Home();
}

final class _Login extends _AppRoute {
  const _Login();
}

// VIOLATION: returns the proposed stack unchanged — a no-op guard.
final KaiselGuard<_AppRoute> _passThrough = (current, proposed) => proposed;
//                                          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
//                                          unused_guard_redirect

// VIOLATION: every branch returns proposed — the redirect was probably meant
// to return a different stack on one path.
final KaiselGuard<_AppRoute> _alwaysProposed = (current, proposed) {
  if (current.isEmpty) return proposed;
  return proposed;
};

// CORRECT: actually redirects on one path — not flagged.
final KaiselGuard<_AppRoute> _authGuard = (current, proposed) {
  if (proposed.isEmpty) return const [_Login()];
  return proposed;
};

// CORRECT: kept for a side effect (logging), so its body has a non-return
// statement — not flagged.
final KaiselGuard<_AppRoute> _logging = (current, proposed) {
  print('navigating to ${proposed.length} routes');
  return proposed;
};
