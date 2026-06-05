// Fix: add `const` to a KaiselRoute construction flagged by
// prefer_const_route_constructors. Replaces a leading `new` keyword if
// present, otherwise inserts `const` before the expression.

import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';

class UseConstRouteConstructorFix extends ResolvedCorrectionProducer {
  UseConstRouteConstructorFix({required super.context});

  static const FixKind _kind = FixKind(
    'kaisel_lint.use_const_route_constructor',
    DartFixKindPriority.standard,
    'Add const',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.automatically;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    // The diagnostic spans the whole construction, so `node` may be a child
    // (the constructor name) — walk up to the invocation.
    final invocation = node.thisOrAncestorOfType<InstanceCreationExpression>();
    if (invocation == null) return;
    if (invocation.isConst) return;

    await builder.addDartFileEdit(file, (b) {
      final keyword = invocation.keyword;
      if (keyword != null) {
        b.addSimpleReplacement(range.token(keyword), 'const');
      } else {
        b.addSimpleInsertion(invocation.offset, 'const ');
      }
    });
  }
}
