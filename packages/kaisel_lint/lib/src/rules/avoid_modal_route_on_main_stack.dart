// Lint: avoid_modal_route_on_main_stack
//
// Flags `router.push(modalRoute)` where the argument's static type
// implements `KaiselModalRoute<T>`. The mechanical workaround "works"
// — the page renders — but silently loses the typed completion
// contract. The caller of `run<T>` awaits a `Future<T?>`; there's no
// equivalent on `push`, so the flow's typed result is dropped on the
// floor.
//
// False-positive surface is essentially zero: a route only implements
// `KaiselModalRoute<T>` when the author intended it to be opened as a
// flow.

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../lint_codes.dart';
import '../utils/kaisel_types.dart';

class AvoidModalRouteOnMainStack extends AnalysisRule {
  AvoidModalRouteOnMainStack()
    : super(
        name: 'avoid_modal_route_on_main_stack',
        description:
            'Pushing a KaiselModalRoute via push() loses its '
            'typed-completion contract.',
      );

  @override
  DiagnosticCode get diagnosticCode => avoidModalRouteOnMainStack;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry.addMethodInvocation(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AvoidModalRouteOnMainStack rule;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name != 'push') return;

    // Must have a receiver to inspect — bare push() calls don't apply.
    final target = node.realTarget;
    if (target == null) return;

    final targetType = target.staticType;
    if (targetType == null) return;
    if (!isKaiselRouterType(targetType)) return;

    // Must have a first argument.
    final args = node.argumentList.arguments;
    if (args.isEmpty) return;

    final argType = args.first.argumentExpression.staticType;
    if (argType == null) return;

    // Argument's static type must implement KaiselModalRoute<T>.
    if (getKaiselModalRouteTypeArgument(argType) == null) return;

    rule.reportAtNode(node);
  }
}
