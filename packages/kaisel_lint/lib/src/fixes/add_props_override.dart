// Fix: add `@override List<Object?> get props => [...]` to a
// KaiselRoute subclass that's missing it. The fix collects every
// instance field declared by the class and builds a props list naming
// each, inserting it just before the class's closing brace (or giving a
// bodyless primary-constructor class a body).

import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

import '../utils/kaisel_types.dart';
import '../utils/props_override.dart';

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
    // The diagnostic is reported on the class name token, so `node` is the
    // identifier — walk up to the enclosing declaration.
    final classDecl = node.thisOrAncestorOfType<ClassDeclaration>();
    if (classDecl == null) return;

    final element = classDecl.declaredFragment?.element;
    if (element == null) return;

    final fieldNames = declaredInstanceFields(element)
        .map((f) => f.name)
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList();

    if (fieldNames.isEmpty) return;

    await builder.addDartFileEdit(file, (b) {
      addPropsOverride(b, classDecl, fieldNames);
    });
  }
}
