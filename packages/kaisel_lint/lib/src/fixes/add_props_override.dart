// Fix: add `@override List<Object?> get props => [...]` to a
// KaiselRoute subclass that's missing it. The fix collects every
// instance field declared by the class and builds a props list naming
// each, inserting it just before the class's closing brace.

import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

import '../utils/kaisel_types.dart';

class AddPropsOverrideFix extends ResolvedCorrectionProducer {
  AddPropsOverrideFix({required super.context});

  static const FixKind _kind = FixKind(
    'kaisel_lint.add_props_override',
    DartFixKindPriority.standard,
    "Add props override",
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.automatically;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final node = this.node;
    if (node is! ClassDeclaration) return;

    final element = node.declaredFragment?.element;
    if (element == null) return;

    final fieldNames = declaredInstanceFields(element)
        .map((f) => f.name)
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList();

    if (fieldNames.isEmpty) return;

    final propsList = fieldNames.join(', ');
    final insertion =
        '\n\n  @override\n'
        '  List<Object?> get props => [$propsList];';

    await builder.addDartFileEdit(file, (b) {
      // Insert directly before the closing brace (`node.end - 1` is the
      // offset of the class's `}`). Two newlines and matching indent
      // produce idiomatic spacing in the generated class body.
      b.addSimpleInsertion(node.end - 1, insertion);
    });
  }
}
