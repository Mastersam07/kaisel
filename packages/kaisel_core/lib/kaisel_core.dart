/// Pure-Dart navigation core for the kaisel router.
///
/// Sealed routes, a stack-as-state [KaiselRouter], a guard pipeline, and URL
/// codecs — with no Flutter dependency. The Flutter widgets (delegate, shells,
/// modules, adaptive layouts) live in the `kaisel` package, which re-exports
/// everything here.
library;

export 'src/kaisel_codec.dart';
export 'src/kaisel_config.dart'
    show
        KaiselConfig,
        KaiselConfigCodec,
        KaiselModuleConfig,
        KaiselNestedConfig,
        KaiselShellConfig,
        StackToConfigCodec;
export 'src/kaisel_guard.dart';
export 'src/kaisel_module_codec.dart'
    show
        ConfigCodecWithModules,
        ModuleMount,
        ModuleStackCodec,
        UntypedModuleStackCodec;
export 'src/kaisel_route.dart';
export 'src/kaisel_router.dart'
    show
        KaiselActiveFlow,
        KaiselNavigator,
        KaiselRouter,
        KaiselTransitionCallback;
export 'src/kaisel_stack_codec.dart';
