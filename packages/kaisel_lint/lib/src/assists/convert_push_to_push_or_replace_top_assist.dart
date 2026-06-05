// Assist: convert any `.push(route)` to `.pushOrReplaceTop(route)`,
// available whenever the cursor sits on a router push invocation.
// Useful when a developer realises mid-refactor that a specific call
// site is adaptive without enabling the off-by-default
// prefer_push_or_replace_top_in_adaptive lint for the whole project.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';

import '../utils/kaisel_types.dart';

class ConvertPushToPushOrReplaceTopAssist extends ResolvedCorrectionProducer {
  ConvertPushToPushOrReplaceTopAssist({required super.context});

  static const AssistKind _kind = AssistKind(
    'kaisel_lint.convert_push_to_push_or_replace_top_assist',
    25,
    "Convert push() to pushOrReplaceTop()",
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  AssistKind get assistKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final invocation = node.thisOrAncestorOfType<MethodInvocation>();
    if (invocation == null) return;
    if (invocation.methodName.name != 'push') return;

    final receiver = invocation.realTarget;
    if (receiver == null) return;
    final receiverType = receiver.staticType;
    if (receiverType == null || !isKaiselRouterType(receiverType)) return;

    // Don't offer this assist for modal route pushes — the
    // convert-to-run assist is the right transformation there.
    final args = invocation.argumentList.arguments;
    if (args.isNotEmpty) {
      final argType = args.first.staticType;
      if (argType != null && getKaiselModalRouteTypeArgument(argType) != null) {
        return;
      }
    }

    await builder.addDartFileEdit(file, (b) {
      b.addSimpleReplacement(
        range.node(invocation.methodName),
        'pushOrReplaceTop',
      );
    });
  }
}
