// Lint: prefer_push_or_replace_top_in_adaptive
//
// Off by default (info severity). When enabled, flags every
// `router.push(route)` call where the route is a non-modal KaiselRoute
// — encouraging the consistent use of `pushOrReplaceTop` in projects
// that use adaptive master-detail.
//
// We can't statically detect "this code path runs under an adaptive
// builder" — adaptivity is a runtime decision based on width. So the
// rule trades precision for opt-in scope: users enable it on projects
// where they know adaptive branches exist; the documentation explains
// when to enable vs. ignore.

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../lint_codes.dart';
import '../utils/kaisel_types.dart';

class PreferPushOrReplaceTopInAdaptive extends AnalysisRule {
  PreferPushOrReplaceTopInAdaptive()
    : super(
        name: 'prefer_push_or_replace_top_in_adaptive',
        description:
            'In adaptive master-detail layouts, push() stacks '
            'duplicate details; use pushOrReplaceTop().',
      );

  @override
  DiagnosticCode get diagnosticCode => preferPushOrReplaceTopInAdaptive;

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

  final PreferPushOrReplaceTopInAdaptive rule;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name != 'push') return;

    final target = node.realTarget;
    if (target == null) return;

    final targetType = target.staticType;
    if (targetType == null) return;
    if (!isKaiselRouterType(targetType)) return;

    final args = node.argumentList.arguments;
    if (args.isEmpty) return;

    final argType = args.first.staticType;
    if (argType == null) return;

    // Don't double-fire on modal route pushes — the dedicated rule
    // (`avoid_modal_route_on_main_stack`) covers those with a
    // different fix (`run<T>`, not `pushOrReplaceTop`).
    if (getKaiselModalRouteTypeArgument(argType) != null) return;

    rule.reportAtNode(node);
  }
}
