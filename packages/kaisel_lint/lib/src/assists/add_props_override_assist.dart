// Assist: add a `@override List<Object?> get props => [...]` to a
// KaiselRoute subclass under the cursor. Available even when the class
// doesn't yet violate `require_route_props` — useful pre-emptively
// before adding fields.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';

import '../utils/kaisel_types.dart';

class AddPropsOverrideAssist extends ResolvedCorrectionProducer {
  AddPropsOverrideAssist({required super.context});

  static const AssistKind _kind = AssistKind(
    'kaisel_lint.add_props_override_assist',
    30,
    "Add props override",
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  AssistKind get assistKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    // Walk up to find an enclosing ClassDeclaration.
    final classDecl = node.thisOrAncestorOfType<ClassDeclaration>();
    if (classDecl == null) return;

    final element = classDecl.declaredFragment?.element;
    if (element == null) return;
    if (!extendsKaiselRoute(element)) return;

    // No-op if a props override is already present.
    if (overridesProps(element)) return;

    final fieldNames = declaredInstanceFields(element)
        .map((f) => f.name)
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList();

    final propsList = fieldNames.join(', ');
    final insertion =
        '\n  @override\n'
        '  List<Object?> get props => [$propsList];\n';

    await builder.addDartFileEdit(file, (b) {
      // `classDecl.end - 1` is the offset of the class's closing `}`.
      b.addSimpleInsertion(classDecl.end - 1, insertion);
    });
  }
}
