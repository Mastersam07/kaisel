// Fix: convert `.push(modalRoute)` to `.run<T>(modalRoute)`.
//
// Attached to the avoid_modal_route_on_main_stack diagnostic via
// `registry.registerFixForRule` in plugin.dart. The type argument T is
// recovered from the route's KaiselModalRoute<T> implementation when
// possible, so the fix produces compilable code in one shot.

import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';

import '../utils/kaisel_types.dart';

class ConvertPushToRunFix extends ResolvedCorrectionProducer {
  ConvertPushToRunFix({required super.context});

  static const FixKind _kind = FixKind(
    'kaisel_lint.convert_push_to_run',
    DartFixKindPriority.standard,
    "Convert push() to run<T>()",
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

    final args = node.argumentList.arguments;
    if (args.isEmpty) return;

    final argType = args.first.staticType;
    if (argType == null) return;

    final typeArg = getKaiselModalRouteTypeArgument(argType);
    final typeArgDisplay = typeArg?.getDisplayString();

    final replacement = typeArgDisplay != null ? 'run<$typeArgDisplay>' : 'run';

    await builder.addDartFileEdit(file, (b) {
      b.addSimpleReplacement(range.node(node.methodName), replacement);
    });
  }
}
