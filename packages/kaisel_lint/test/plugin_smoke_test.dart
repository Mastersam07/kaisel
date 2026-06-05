// Smoke test for the declaration-only files: main.dart's `plugin` entry point
// and lint_codes.dart's shared diagnostic codes. They carry no behaviour, so
// the rule and PluginServer suites never touch them — this does, directly.

import 'package:kaisel_lint/main.dart' as entrypoint;
import 'package:kaisel_lint/src/lint_codes.dart';
import 'package:test/test.dart';

void main() {
  test('entry point exposes the kaisel_lint plugin', () {
    expect(entrypoint.plugin.name, 'kaisel_lint');
  });

  test('diagnostic codes carry their rule names', () {
    expect(
      avoidModalRouteOnMainStack.lowerCaseName,
      'avoid_modal_route_on_main_stack',
    );
    expect(requireRouteProps.lowerCaseName, 'require_route_props');
    expect(
      preferPushOrReplaceTopInAdaptive.lowerCaseName,
      'prefer_push_or_replace_top_in_adaptive',
    );
  });
}
