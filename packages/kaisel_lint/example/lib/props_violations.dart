// Demonstrations of `require_route_props`.
//
// Each class declaration that fields-but-no-props is annotated with
// the expected diagnostic. The quick fix generates a props override
// from the declared instance fields.

// ignore_for_file: unused_element, unused_element_parameter

import 'package:kaisel/kaisel.dart';

// VIOLATION: declares `id` but no props override.
// The fix adds: `@override List<Object?> get props => [id];`
final class _OrderDetail extends KaiselRoute {
  //         ^^^^^^^^^^^ require_route_props
  const _OrderDetail(this.id);
  final String id;
}

// VIOLATION: declares multiple fields, no props. The fix lists all of
// them in the generated override.
final class _FilteredList extends KaiselRoute {
  //         ^^^^^^^^^^^^ require_route_props
  const _FilteredList({
    required this.category,
    required this.sortBy,
    this.page = 1,
  });
  final String category;
  final String sortBy;
  final int page;
}

// CORRECT: no fields → no rule fires. Routes with no parameters don't
// need props because identity equality is already correct.
final class _Empty extends KaiselRoute {
  const _Empty();
}

// CORRECT: declares fields AND overrides props.
final class _Properly extends KaiselRoute {
  const _Properly(this.name);
  final String name;

  @override
  List<Object?> get props => [name];
}
