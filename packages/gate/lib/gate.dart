/// A Dart 3-native Flutter router built on sealed routes, pattern matching,
/// and a stack-as-state model.
///
/// Re-exports the pure-Dart navigation core (`package:gate_core`) — routes,
/// the router, guards, and URL codecs — alongside the Flutter layer: the
/// router delegate, shells, modules, adaptive layouts, transitions, and page
/// scope. Importing `package:gate/gate.dart` gives you the whole surface.
library;

export 'package:gate_core/gate_core.dart';

export 'src/gate_adaptive.dart'
    show
        GateAbsorbingPage,
        GateAdaptivePageBuilder,
        GateMasterDetailScaffold,
        GatePageResult,
        GateStackContext,
        GateStandalonePage;
export 'src/gate_branched_shell.dart'
    show
        BranchedShellRouter,
        BranchedShellScope,
        GateBranch,
        GateBranchedShell,
        GateBranchedShellChromeBuilder,
        GateBranchedShellContextX;
export 'src/gate_inner_navigator.dart';
export 'src/gate_module.dart' show GateModuleMount, RouteModule;
export 'src/gate_page_scope.dart' show GatePageScope;
export 'src/gate_page_wrapper.dart'
    show GatePageWrapper, GatePageWrapperContext;
export 'src/gate_route_information_parser.dart';
export 'src/gate_router_delegate.dart'
    show GateModalBuilder, GatePageBuilder, GateRouterDelegate;
export 'src/gate_scope.dart';
export 'src/gate_shell.dart'
    show
        GateBranchScope,
        GateShellBuildContextX,
        GateShell,
        GateShellChromeBuilder,
        ShellRouter,
        ShellScope;
