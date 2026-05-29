/// A Dart 3-native Flutter router built on sealed routes, pattern
/// matching, and a stack-as-state model.
///
/// See the README for a full walkthrough.
library;

export 'src/gate_codec.dart';
export 'src/gate_guard.dart';
export 'src/gate_route.dart';
export 'src/gate_route_information_parser.dart';
export 'src/gate_router.dart' show GateRouter;
export 'src/gate_router_delegate.dart';
export 'src/gate_shell.dart'
    show
        GateBranchScope,
        GateBuildContextX,
        GateShell,
        GateShellChromeBuilder,
        ShellRouter,
        ShellScope;
