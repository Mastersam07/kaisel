// Shared diagnostic codes for kaisel_lint rules.
//
// Pulled out into one file so:
//
//  - Each rule can reference its own code without circular imports
//    when the fix layer needs to register against the same code.
//  - The set of rule names is visible at a glance — useful when
//    documenting enable/disable in `analysis_options.yaml`.
//
// Severities follow the analyzer plugin convention: rules that catch
// silent bug classes are warnings; rules that catch stylistic
// inconsistencies are info-level. Adaptive-pattern rule is info so
// it doesn't shout in normal codebases.

import 'package:analyzer/error/error.dart';

/// Diagnostic emitted when a `KaiselModalRoute` is pushed onto a router
/// via `push()` instead of opened via `run<T>()`. The flow's typed
/// completion contract is silently lost.
const DiagnosticCode avoidModalRouteOnMainStack = LintCode(
  'avoid_modal_route_on_main_stack',
  'Pushing a KaiselModalRoute via push() loses its typed-completion '
      'contract. The flow renders but its result is unreachable.',
  correctionMessage:
      'Use router.run<T>() to open this as a typed flow and receive '
      'its result.',
  severity: DiagnosticSeverity.WARNING,
);

/// Diagnostic emitted when a `KaiselRoute` subclass declares instance
/// fields without overriding `props`. Without value equality, the stack
/// treats equal-by-value routes as distinct entries.
const DiagnosticCode requireRouteProps = LintCode(
  'require_route_props',
  'KaiselRoute subclasses with instance fields must override props to '
      'enable value equality. Without it, the stack treats equal routes '
      'as distinct entries.',
  correctionMessage:
      'Add @override List<Object?> get props => [...] listing every '
      'instance field.',
  severity: DiagnosticSeverity.WARNING,
);

/// Diagnostic emitted when a router push could be a pushOrReplaceTop in
/// an adaptive context. Off by default — users opt in per project when
/// they know adaptive branches exist.
const DiagnosticCode preferPushOrReplaceTopInAdaptive = LintCode(
  'prefer_push_or_replace_top_in_adaptive',
  'In adaptive master-detail layouts, push() stacks duplicate details. '
      'Use pushOrReplaceTop() so selecting a different detail swaps in '
      'place instead of accumulating a deep stack.',
  correctionMessage:
      'Replace push() with pushOrReplaceTop() if this call lives inside '
      'an adaptive branch.',
  severity: DiagnosticSeverity.INFO,
);
