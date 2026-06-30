// Lint: require_route_props
//
// Flags KaiselRoute subclasses that declare instance fields but don't
// override `props`. Without the override, two routes with the same
// field values are unequal (default Object equality is identity-based),
// which breaks stack diffing, equality-based deduplication, and
// `pushOrReplaceTop`'s same-route detection.

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../lint_codes.dart';
import '../utils/kaisel_types.dart';

class RequireRouteProps extends AnalysisRule {
  RequireRouteProps()
    : super(
        name: 'require_route_props',
        description:
            'KaiselRoute subclasses with instance fields must '
            'override props for value equality.',
      );

  @override
  DiagnosticCode get diagnosticCode => requireRouteProps;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry.addClassDeclaration(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final RequireRouteProps rule;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final element = node.declaredFragment?.element;
    if (element == null) return;

    // Must be a KaiselRoute subclass.
    if (!extendsKaiselRoute(element)) return;

    // Must declare at least one instance field. Abstract bases and
    // sealed-root classes with no fields exist as type roots only and
    // don't need props.
    final fields = declaredInstanceFields(element).toList();
    if (fields.isEmpty) return;

    // Must NOT already override props.
    if (overridesProps(element)) return;

    rule.reportAtToken(node.namePart.typeName);
  }
}
