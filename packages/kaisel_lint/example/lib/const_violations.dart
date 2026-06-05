// Demonstrations of `prefer_const_route_constructors`.
//
// A KaiselRoute construction that *could* be const but isn't is flagged.
// The quick fix inserts the `const` keyword. Constructions that can't be
// const (non-const constructor, or non-constant arguments) are left alone.

// ignore_for_file: unused_local_variable

import 'package:kaisel/kaisel.dart';

final class _Settings extends KaiselRoute {
  const _Settings();

  @override
  List<Object?> get props => const [];
}

final class _Profile extends KaiselRoute {
  const _Profile(this.id);
  final String id;

  @override
  List<Object?> get props => [id];
}

void examples(String runtimeId) {
  // VIOLATION: const constructor, no arguments — can be const.
  final a = _Settings();
  //        ^^^^^^^^^^^ prefer_const_route_constructors

  // VIOLATION: const-constructible with a constant argument.
  final b = _Profile('user-1');
  //        ^^^^^^^^^^^^^^^^^^^ prefer_const_route_constructors

  // CORRECT: already const.
  const c = _Settings();

  // CORRECT: the argument isn't a constant, so it can't be const — no lint.
  final d = _Profile(runtimeId);
}
