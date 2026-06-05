// Entry point for the kaisel_lint analysis server plugin.
//
// The Dart analysis server loads the top-level `plugin` variable from
// this file when the host project's `analysis_options.yaml` enables
// `kaisel_lint` under its `plugins:` section. This file should remain
// minimal — the real wiring lives in `src/plugin.dart`.

import 'package:analysis_server_plugin/plugin.dart';

import 'src/plugin.dart';

final Plugin plugin = KaiselLintPlugin();
