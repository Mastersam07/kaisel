// KaiselLintPlugin — the analysis server plugin that bundles every
// kaisel_lint rule, fix, and assist.
//
// Registration is the load-bearing wiring: each rule is attached to
// the registry so it shows up in `dart analyze` and the IDE; each fix
// is bound to its rule's diagnostic code so the IDE's quick-fix menu
// surfaces it; each assist is registered without a binding code so
// it's available based on cursor position.

import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'assists/add_props_override_assist.dart';
import 'assists/convert_push_to_push_or_replace_top_assist.dart';
import 'assists/convert_push_to_run_assist.dart';
import 'fixes/add_props_override.dart';
import 'fixes/convert_push_to_push_or_replace_top.dart';
import 'fixes/convert_push_to_run.dart';
import 'fixes/use_const_route_constructor.dart';
import 'lint_codes.dart';
import 'rules/avoid_modal_route_on_main_stack.dart';
import 'rules/prefer_const_route_constructors.dart';
import 'rules/prefer_pattern_match_over_is_check.dart';
import 'rules/prefer_push_or_replace_top_in_adaptive.dart';
import 'rules/require_route_props.dart';

class KaiselLintPlugin extends Plugin {
  @override
  String get name => 'kaisel_lint';

  @override
  void register(PluginRegistry registry) {
    registry.registerLintRule(AvoidModalRouteOnMainStack());
    registry.registerLintRule(RequireRouteProps());
    registry.registerLintRule(PreferPushOrReplaceTopInAdaptive());
    registry.registerLintRule(PreferConstRouteConstructors());
    registry.registerLintRule(PreferPatternMatchOverIsCheck());

    registry.registerFixForRule(
      avoidModalRouteOnMainStack,
      ConvertPushToRunFix.new,
    );
    registry.registerFixForRule(requireRouteProps, AddPropsOverrideFix.new);
    registry.registerFixForRule(
      preferPushOrReplaceTopInAdaptive,
      ConvertPushToPushOrReplaceTopFix.new,
    );
    registry.registerFixForRule(
      preferConstRouteConstructors,
      UseConstRouteConstructorFix.new,
    );

    registry.registerAssist(ConvertPushToRunAssist.new);
    registry.registerAssist(AddPropsOverrideAssist.new);
    registry.registerAssist(ConvertPushToPushOrReplaceTopAssist.new);
  }
}
