/// Analysis-server plugin entrypoint for gate_lint.
///
/// **Scaffold only** — registers no rules yet. Built on the first-party
/// `analysis_server_plugin` API (the SDK's plugin mechanism), not community
/// `custom_lint`. Consumers will enable it via the `plugins:` section of their
/// `analysis_options.yaml` once rules ship.
///
/// Roadmap candidates: `prefer_push_or_replace_top_in_adaptive`,
/// `avoid_modal_route_on_main_stack`, `prefer_const_route_constructors`.
library;

import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

/// The plugin instance the analysis server discovers and loads.
final Plugin plugin = _GateLintPlugin();

class _GateLintPlugin extends Plugin {
  @override
  String get name => 'gate_lint';

  @override
  void register(PluginRegistry registry) {
    // No rules yet. Register them here as they are implemented, e.g.:
    //   registry.registerLintRule(PreferPushOrReplaceTopInAdaptive());
  }
}
