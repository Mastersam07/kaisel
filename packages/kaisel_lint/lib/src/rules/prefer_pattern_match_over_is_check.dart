// Lint: prefer_pattern_match_over_is_check
//
// Flags `route is SomeRoute` — a runtime type test that branches on which
// concrete route is held — where a `switch (route) { ... }` (or an
// `if (route case SomeRoute())` pattern) reads better. Routes are sealed
// value types, so a switch is exhaustive and destructures fields without a
// cast, whereas chained is-checks are easy to leave non-exhaustive.
//
// The trigger is deliberately narrow to keep false positives low: it fires
// only on a positive `is` where BOTH the tested expression and the tested
// type are KaiselRoute subtypes. Capability checks like `is KaiselModalRoute`
// or `is Comparable`, and `is!` narrowing guards, are left alone.
//
// There is no quick fix: the safe rewrite is contextual (a single check
// becomes an `if (route case ...)`, a chain becomes a `switch`), and naively
// rebinding the variable can collide with a body-local of the same name.

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import '../lint_codes.dart';
import '../utils/kaisel_types.dart';

class PreferPatternMatchOverIsCheck extends AnalysisRule {
  PreferPatternMatchOverIsCheck()
    : super(
        name: 'prefer_pattern_match_over_is_check',
        description: 'Prefer a switch/pattern match over is-checks on routes.',
      );

  @override
  DiagnosticCode get diagnosticCode => preferPatternMatchOverIsCheck;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry.addIsExpression(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final PreferPatternMatchOverIsCheck rule;

  @override
  void visitIsExpression(IsExpression node) {
    // `is!` is usually a narrowing guard (`if (route is! Home) return;`),
    // which a switch expresses poorly — leave it alone.
    if (node.notOperator != null) return;

    // The tested expression must be a KaiselRoute value.
    final operandType = node.expression.staticType;
    if (operandType is! InterfaceType) return;
    if (!extendsKaiselRoute(operandType.element)) return;

    // The tested type must be a route subtype declared by the user — the
    // "which route is this" case. Framework types declared by kaisel itself
    // (`KaiselRoute`, `KaiselModalRoute`, …) are capability/marker checks and
    // are left alone, even though they extend `KaiselRoute`.
    final testedType = node.type.type;
    if (testedType is! InterfaceType) return;
    final testedElement = testedType.element;
    if (!extendsKaiselRoute(testedElement)) return;
    if (isFromKaiselPackage(testedElement)) return;

    rule.reportAtNode(node);
  }
}
