// Demonstrations of `prefer_pattern_match_over_is_check`.
//
// `is` checks that branch on which concrete route is held read better as a
// switch (pattern match) over the sealed route type. The rule has no quick
// fix — the safe rewrite is contextual (a single check becomes an
// `if (route case ...)`, a chain becomes a `switch`).

// ignore_for_file: unused_element

import 'package:kaisel/kaisel.dart';

sealed class _AppRoute extends KaiselRoute {
  const _AppRoute();
}

final class _Home extends _AppRoute {
  const _Home();
}

final class _Detail extends _AppRoute {
  const _Detail(this.id);
  final String id;

  @override
  List<Object?> get props => [id];
}

// VIOLATION: branching on the concrete route via chained `is` checks.
String _describe(_AppRoute route) {
  if (route is _Home) return 'home';
  //  ^^^^^^^^^^^^^ prefer_pattern_match_over_is_check
  if (route is _Detail) return route.id;
  //  ^^^^^^^^^^^^^^^ prefer_pattern_match_over_is_check
  return '';
}

// CORRECT: the same logic as an exhaustive switch — no lint.
String _describeOk(_AppRoute route) => switch (route) {
  _Home() => 'home',
  _Detail(:final id) => id,
};

// CORRECT: a capability check against a marker interface, not a concrete
// route type — left alone.
bool _isModal(_AppRoute route) => route is KaiselModalRoute<void>;
