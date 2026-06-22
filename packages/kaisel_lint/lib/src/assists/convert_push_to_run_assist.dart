// Assist: convert any `.push(modalRoute)` to `.run<T>(modalRoute)`,
// available whenever the cursor sits on a qualifying invocation —
// regardless of whether the avoid_modal_route_on_main_stack lint is
// enabled.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';

import '../utils/kaisel_types.dart';

class ConvertPushToRunAssist extends ResolvedCorrectionProducer {
  ConvertPushToRunAssist({required super.context});

  static const AssistKind _kind = AssistKind(
    'kaisel_lint.convert_push_to_run_assist',
    30,
    "Convert push() to run<T>()",
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  AssistKind get assistKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    // Walk up from the selection to find an enclosing MethodInvocation.
    final invocation = node.thisOrAncestorOfType<MethodInvocation>();
    if (invocation == null) return;
    if (invocation.methodName.name != 'push') return;

    // Receiver must be a kaisel router.
    final receiver = invocation.realTarget;
    if (receiver == null) return;
    final receiverType = receiver.staticType;
    if (receiverType == null || !isKaiselRouterType(receiverType)) return;

    // Argument must be a KaiselModalRoute.
    final args = invocation.argumentList.arguments;
    if (args.isEmpty) return;
    final argType = args.first.argumentExpression.staticType;
    if (argType == null) return;
    final typeArg = getKaiselModalRouteTypeArgument(argType);
    if (typeArg == null) return;

    final typeArgDisplay = typeArg.getDisplayString();

    await builder.addDartFileEdit(file, (b) {
      b.addSimpleReplacement(
        range.node(invocation.methodName),
        'run<$typeArgDisplay>',
      );
    });
  }
}
