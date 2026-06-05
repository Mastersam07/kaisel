// Lint: prefer_const_route_constructors
//
// A KaiselRoute-scoped variant of the standard prefer_const_constructors
// lint. Flags a non-const construction of a KaiselRoute subclass that
// could be const, so a project can enforce const-correctness for routes
// without turning prefer_const_constructors on for every class.
//
// Const routes matter more than const values in general: routes are value
// types that the stack compares constantly, and const instances are
// canonicalised so equal routes share identity.

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import '../lint_codes.dart';
import '../utils/kaisel_types.dart';

class PreferConstRouteConstructors extends AnalysisRule {
  PreferConstRouteConstructors()
    : super(
        name: 'prefer_const_route_constructors',
        description:
            'KaiselRoute constructions that can be const should be const.',
      );

  @override
  DiagnosticCode get diagnosticCode => preferConstRouteConstructors;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry.addInstanceCreationExpression(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final PreferConstRouteConstructors rule;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // Already const — explicitly, or implicitly inside a const context.
    if (node.isConst) return;

    // Must construct a KaiselRoute subtype.
    final type = node.staticType;
    if (type is! InterfaceType) return;
    if (!extendsKaiselRoute(type.element)) return;

    // Must actually be const-able: const constructor, constant arguments, and
    // no error if evaluated. `canBeConst` does this work for us.
    if (!node.canBeConst) return;

    rule.reportAtNode(node);
  }
}
