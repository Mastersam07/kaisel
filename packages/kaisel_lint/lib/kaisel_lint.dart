/// Static analysis rules, quick fixes, and assists for the
/// [kaisel](https://pub.dev/packages/kaisel) Flutter router, built as a
/// first-party analysis server plugin.
///
/// This is a tooling package — you don't import it in application code. The
/// analysis server loads the plugin from `lib/main.dart`; this library exists
/// as the documented entry point and re-exports the rule classes for tooling
/// that wants to reference them.
///
/// ## Rules
///
/// - `avoid_modal_route_on_main_stack` (warning) — flags
///   `router.push(modalRoute)` where the argument implements
///   `KaiselModalRoute<T>`, which silently drops the flow's typed result.
/// - `require_route_props` (warning) — flags `KaiselRoute` subclasses with
///   instance fields that don't override `props`, breaking value equality.
/// - `prefer_push_or_replace_top_in_adaptive` (info, off by default) — flags
///   `router.push(route)` in projects using adaptive master-detail.
///
/// ## Usage
///
/// Enable the plugin in your project's `analysis_options.yaml`:
///
/// ```yaml
/// plugins:
///   kaisel_lint:
///     version: ^0.1.0
///     diagnostics:
///       avoid_modal_route_on_main_stack: true
///       require_route_props: true
///       prefer_push_or_replace_top_in_adaptive: false # opt-in per project
/// ```
///
/// See the package README for the full rule reference, quick fixes, and
/// assists.
library;

export 'src/rules/avoid_modal_route_on_main_stack.dart';
export 'src/rules/prefer_push_or_replace_top_in_adaptive.dart';
export 'src/rules/require_route_props.dart';
