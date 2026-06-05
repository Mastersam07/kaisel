// Fix: convert `.push(route)` to `.pushOrReplaceTop(route)`. Attached
// to the `prefer_push_or_replace_top_in_adaptive` diagnostic. Purely
// textual transformation — same argument list, same return type, only
// the method name changes.

import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';

class ConvertPushToPushOrReplaceTopFix extends ResolvedCorrectionProducer {
  ConvertPushToPushOrReplaceTopFix({required super.context});

  static const FixKind _kind = FixKind(
    'kaisel_lint.convert_push_to_push_or_replace_top',
    DartFixKindPriority.standard,
    "Convert push() to pushOrReplaceTop()",
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.automatically;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final node = this.node;
    if (node is! MethodInvocation) return;
    if (node.methodName.name != 'push') return;

    await builder.addDartFileEdit(file, (b) {
      b.addSimpleReplacement(range.node(node.methodName), 'pushOrReplaceTop');
    });
  }
}
