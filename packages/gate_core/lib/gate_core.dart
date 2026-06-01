/// Pure-Dart navigation core for the gate router.
///
/// Sealed routes, a stack-as-state [GateRouter], a guard pipeline, and URL
/// codecs — with no Flutter dependency. The Flutter widgets (delegate, shells,
/// modules, adaptive layouts) live in the `gate` package, which re-exports
/// everything here.
library;

export 'src/gate_codec.dart';
export 'src/gate_config.dart'
    show
        GateConfig,
        GateConfigCodec,
        GateModuleConfig,
        GateNestedConfig,
        GateShellConfig,
        StackToConfigCodec;
export 'src/gate_guard.dart';
export 'src/gate_module_codec.dart'
    show
        ConfigCodecWithModules,
        ModuleMount,
        ModuleStackCodec,
        UntypedModuleStackCodec;
export 'src/gate_route.dart';
export 'src/gate_router.dart' show GateActiveFlow, GateNavigator, GateRouter;
export 'src/gate_stack_codec.dart';
