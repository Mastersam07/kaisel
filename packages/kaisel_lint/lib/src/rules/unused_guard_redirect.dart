// Lint: unused_guard_redirect
//
// Flags a `KaiselGuard` closure that returns the proposed stack unchanged on
// every path — a no-op guard with no effect on navigation. Either it's dead
// code, or a redirect branch that was meant to return a different stack was
// left returning `proposed`.
//
// Detection is deliberately conservative to avoid false positives:
//
//  - The closure must be guard-shaped: two positional `List<R>` parameters
//    with `R` a KaiselRoute subtype.
//  - Every return must return the *second* parameter (`proposed`) directly.
//  - The body must contain nothing but returns, ifs, and blocks. A guard kept
//    for a side effect (logging, analytics) that still returns `proposed` has
//    some other statement in its body, so it is left alone.
//
// There is no quick fix: removing a guard means editing the `guards:` list,
// which is contextual.

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import '../lint_codes.dart';
import '../utils/kaisel_types.dart';

class UnusedGuardRedirect extends AnalysisRule {
  UnusedGuardRedirect()
    : super(
        name: 'unused_guard_redirect',
        description:
            'A guard that returns the proposed stack unchanged is a no-op.',
      );

  @override
  DiagnosticCode get diagnosticCode => unusedGuardRedirect;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addFunctionExpression(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final UnusedGuardRedirect rule;

  @override
  void visitFunctionExpression(FunctionExpression node) {
    final params = node.parameters?.parameters;
    if (params == null || params.length != 2) return;
    if (params.any((p) => !p.isPositional)) return;

    // The KaiselGuard shape: `(List<R> current, List<R> proposed) -> List<R>`.
    if (!_isListOfRoute(_typeOf(params[0]))) return;
    if (!_isListOfRoute(_typeOf(params[1]))) return;

    final proposed = params[1].declaredFragment?.element;
    if (proposed == null) return;

    if (!_GuardBody(proposed).alwaysReturnsProposed(node.body)) return;

    rule.reportAtNode(node);
  }

  DartType? _typeOf(FormalParameter param) =>
      param.declaredFragment?.element.type;

  bool _isListOfRoute(DartType? type) {
    if (type is! InterfaceType) return false;
    if (type.element.name != 'List') return false;
    final args = type.typeArguments;
    if (args.length != 1) return false;
    final arg = args.first;
    return arg is InterfaceType && extendsKaiselRoute(arg.element);
  }
}

/// Decides whether every path of a guard body returns [proposed] unchanged,
/// with no statement that could carry a side effect.
class _GuardBody {
  _GuardBody(this.proposed);

  final Element proposed;
  var _sawReturn = false;
  var _ok = true;

  bool alwaysReturnsProposed(FunctionBody body) {
    switch (body) {
      case ExpressionFunctionBody():
        return _isProposed(body.expression);
      case BlockFunctionBody():
        _walk(body.block);
        return _ok && _sawReturn;
      case _:
        return false;
    }
  }

  void _walk(Statement statement) {
    switch (statement) {
      case Block():
        for (final inner in statement.statements) {
          _walk(inner);
        }
      case IfStatement():
        _walk(statement.thenStatement);
        final elseStatement = statement.elseStatement;
        if (elseStatement != null) _walk(elseStatement);
      case ReturnStatement():
        _sawReturn = true;
        if (!_isProposed(statement.expression)) _ok = false;
      case _:
        // Anything else — an expression statement, a variable declaration, a
        // loop — could carry a side effect, so don't flag.
        _ok = false;
    }
  }

  bool _isProposed(Expression? expression) =>
      expression is SimpleIdentifier && expression.element == proposed;
}
