/// A Dart 3-native Flutter router built on sealed routes, pattern
/// matching, and a stack-as-state model.
///
/// See the README for a full walkthrough.
library;

export 'src/gate_branched_shell.dart';
export 'src/gate_codec.dart';
export 'src/gate_guard.dart';
export 'src/gate_inner_navigator.dart';
export 'src/gate_route.dart';
export 'src/gate_route_information_parser.dart';
export 'src/gate_router.dart' show GateNavigator, GateRouter;
export 'src/gate_router_delegate.dart';
export 'src/gate_scope.dart';
export 'src/gate_shell.dart'
    show
        GateBranchScope,
        GateShellBuildContextX,
        GateShell,
        GateShellChromeBuilder,
        ShellRouter,
        ShellScope;
export 'src/gate_stack_codec.dart';
