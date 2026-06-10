/// A Dart 3-native Flutter router built on sealed routes, pattern matching,
/// and a stack-as-state model.
///
/// Re-exports the pure-Dart navigation core (`package:kaisel_core`) — routes,
/// the router, guards, and URL codecs — alongside the Flutter layer: the
/// router delegate, shells, modules, adaptive layouts, transitions, and page
/// scope. Importing `package:kaisel/kaisel.dart` gives you the whole surface.
library;

export 'package:kaisel_core/kaisel_core.dart';

export 'src/kaisel_adaptive.dart'
    show
        KaiselAbsorbingPage,
        KaiselAdaptivePageBuilder,
        KaiselMasterDetailScaffold,
        KaiselPageResult,
        KaiselStackContext,
        KaiselStandalonePage;
export 'src/kaisel_branched_shell.dart'
    show
        BranchedShellRouter,
        KaiselBranch,
        KaiselBranchContentBuilder,
        KaiselBranchSpec,
        KaiselBranchedShell,
        KaiselBranchedShellChromeBuilder;
export 'src/kaisel_inner_navigator.dart';
export 'src/kaisel_listenable.dart'
    show KaiselListenableBuilder, KaiselRouterListenable;
export 'src/kaisel_module.dart' show KaiselModuleMount, RouteModule;
export 'src/kaisel_page_scope.dart' show KaiselPageScope;
export 'src/kaisel_page_wrapper.dart'
    show KaiselPageWrapper, KaiselPageWrapperContext;
export 'src/kaisel_route_information_parser.dart';
export 'src/kaisel_router_config.dart' show KaiselRouterConfig;
export 'src/kaisel_router_delegate.dart'
    show
        KaiselModalBuilder,
        KaiselObserversBuilder,
        KaiselPageBuilder,
        KaiselRouterDelegate;
export 'src/kaisel_scope.dart';
export 'src/kaisel_stack_restorer.dart' show KaiselRouteRestorer;
export 'src/kaisel_shell.dart'
    show KaiselBranchScope, KaiselShell, KaiselShellChromeBuilder, ShellRouter;
