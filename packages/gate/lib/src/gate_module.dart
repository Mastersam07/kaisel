import 'package:flutter/widgets.dart';
import 'package:gate_core/framework.dart';

import 'gate_adaptive.dart';
import 'gate_inner_navigator.dart';
import 'gate_page_wrapper.dart';
import 'gate_router_delegate.dart';
import 'gate_scope.dart';

/// A self-contained routing module.
///
/// A `RouteModule` packages everything a reusable feature needs to
/// expose its own routes: a sealed subtype `R`, an initial stack, a
/// page builder, optional guards, and an optional page wrapper. The
/// host app composes modules by mounting them with [GateModuleMount]
/// at a route in its main stack.
///
/// Modules differ from shells. A shell aggregates multiple parallel
/// branches (tabs) that coexist; a module is a single nested router
/// rendered as a normal page. Both have their own internal stack;
/// the URL story is parallel (see [GateModuleConfig]).
///
/// ```dart
/// sealed class ShopRoute extends GateRoute { const ShopRoute(); }
/// final class ShopHome extends ShopRoute { const ShopHome(); }
/// final class ProductDetail extends ShopRoute {
///   const ProductDetail(this.id);
///   final String id;
///   @override
///   List<Object?> get props => [id];
/// }
///
/// class ShopModule extends RouteModule<ShopRoute> {
///   const ShopModule();
///
///   @override
///   List<ShopRoute> get initialStack => const [ShopHome()];
///
///   @override
///   Widget buildPage(BuildContext context, ShopRoute route) => switch (route) {
///     ShopHome() => const ShopHomeScreen(),
///     ProductDetail(:final id) => ProductDetailScreen(id: id),
///   };
/// }
/// ```
///
/// To mount it from the host app's page builder:
///
/// ```dart
/// Widget buildMainPage(BuildContext context, AppRoute route) => switch (route) {
///   ShopMount() => const GateModuleMount<ShopRoute>(module: ShopModule()),
///   // ... other top-level routes
/// };
/// ```
///
/// A module can ship its own [ModuleStackCodec] (see [codec]) so the
/// host can compose URLs with [ConfigCodecWithModules] without knowing
/// the module's internal URL structure. Modules without a codec are
/// URL-handled entirely by the host's own [GateConfigCodec].
abstract class RouteModule<R extends GateRoute> {
  /// Const constructor so subclasses can be `const`.
  const RouteModule();

  /// The stack the module starts with when mounted. Most modules
  /// return a single-route list; multi-route initial stacks are
  /// supported for cases where the module wants to "open at" a
  /// nested location by default.
  List<R> get initialStack;

  /// Resolves a route in this module to a widget. Pattern-match on
  /// the module's sealed type for compile-time exhaustiveness.
  Widget buildPage(BuildContext context, R route);

  /// Adaptive page builder. Override to enable absorbing pages
  /// inside this module (e.g. master-detail at wide breakpoints).
  /// Default implementation wraps [buildPage] as a standalone page,
  /// so modules that don't override get the same 1:1 behaviour as
  /// before.
  ///
  /// When implementing, pattern-match on `(route, stack.previous)`
  /// and the layout breakpoint to decide between
  /// [GateStandalonePage] and [GateAbsorbingPage]. See
  /// `GateRouterDelegate.adaptive` for the canonical example.
  GatePageResult buildAdaptivePage(
    BuildContext context,
    R route,
    GateStackContext<R> stack,
  ) {
    return GateStandalonePage(buildPage(context, route));
  }

  /// Whether this module uses [buildAdaptivePage] to drive its inner
  /// navigator. Defaults to `false`. Override to return `true` if you
  /// implement [buildAdaptivePage].
  ///
  /// We can't reliably detect overrides at runtime, so modules opt
  /// in explicitly. Setting this to `true` without overriding
  /// [buildAdaptivePage] still works (the default returns a
  /// standalone page); the difference is that the inner navigator
  /// goes through the adaptive pipeline rather than the simple one.
  bool get isAdaptive => false;

  /// Guards run on the module's internal navigation. Module guards
  /// see only the module's stack. They don't compose with the host
  /// router's guards.
  List<GateGuard<R>> get guards => const [];

  /// Optional override of how each route becomes a [Page]. Defaults
  /// to [MaterialPage].
  GatePageWrapper<R>? get pageWrapper => null;

  /// Optional URL codec for this module.
  ///
  /// If provided, the host can use a [ConfigCodecWithModules]
  /// composer to wire URLs automatically without duplicating the
  /// module's URL structure in the host's main codec. If `null`, the
  /// host's main codec is fully responsible for any URL handling
  /// involving this module's routes.
  ModuleStackCodec<R>? get codec => null;
}

/// Thin adapter that exposes a [GateRouter] as a non-generic
/// [GateNestedHandle]. The delegate holds one of these per registered
/// module so it can capture/restore the module's stack without
/// knowing the module's `R`.
class _ModuleHandle<R extends GateRoute> implements GateNestedHandle {
  _ModuleHandle(this._router);

  final GateRouter<R> _router;

  @override
  void addListener(VoidCallback listener) => _router.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _router.removeListener(listener);

  @override
  Type get configType => GateModuleConfig;

  @override
  GateModuleConfig captureConfig() => GateModuleConfig(stack: _router.stack);

  @override
  Future<void> restoreFromConfig(GateNestedConfig config) {
    if (config is! GateModuleConfig) return Future<void>.value();
    return _router.restoreStack(config.stack);
  }
}

/// Mounts a [RouteModule] inside the host app.
///
/// Creates the module's typed [GateRouter] internally; the router
/// lives for the lifetime of this widget. When this widget is
/// unmounted (parent route changes, etc.) the module's state is
/// lost — modules are mount-scoped state containers, not singletons.
///
/// Inside the module's screens, `context.router<R>()` resolves to
/// the module's typed router. `context.router<AppRoute>()` (or
/// whatever the host's route type is) bypasses this scope and finds
/// the host router above — same lookup-by-exact-type semantics as
/// `GateBranch`.
class GateModuleMount<R extends GateRoute> extends StatefulWidget {
  /// Create a mount around [module].
  const GateModuleMount({super.key, required this.module});

  /// The module to mount.
  final RouteModule<R> module;

  @override
  State<GateModuleMount<R>> createState() => _GateModuleMountState<R>();
}

class _GateModuleMountState<R extends GateRoute>
    extends State<GateModuleMount<R>> {
  late GateRouter<R> _router;
  late _ModuleHandle<R> _handle;
  late final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>(
    debugLabel: 'gate-module-$R',
  );

  GateNestedHost? _host;

  @override
  void initState() {
    super.initState();
    _buildRouter();
  }

  void _buildRouter() {
    _router = GateRouter<R>.fromStack(
      widget.module.initialStack,
      guards: widget.module.guards,
    );
    _router.addListener(_onRouterChanged);
    _handle = _ModuleHandle<R>(_router);
  }

  void _disposeRouter() {
    _router.removeListener(_onRouterChanged);
    _router.dispose();
  }

  void _onRouterChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = GateNestedHostScope.maybeOf(context);
    if (!identical(host, _host)) {
      _host?.unregisterNested(_handle);
      _host = host;
      _host?.registerNested(_handle);
    }
  }

  @override
  void didUpdateWidget(GateModuleMount<R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different module instance means rebuild the router. Same
    // instance (typical case for const modules) keeps state.
    if (!identical(oldWidget.module, widget.module)) {
      _host?.unregisterNested(_handle);
      _disposeRouter();
      _buildRouter();
      _host?.registerNested(_handle);
    }
  }

  @override
  void dispose() {
    _host?.unregisterNested(_handle);
    _disposeRouter();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Same pattern as the shell: while the module's router can pop,
      // we intercept and pop within the module. At the module's root,
      // back falls through to the host router.
      canPop: !_router.canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_router.canPop) _router.pop();
      },
      child: RouterScope<R>(
        router: _router,
        child: GateInnerNavigator<R>(
          router: _router,
          navigatorKey: _navKey,
          pageBuilder: widget.module.isAdaptive
              ? null
              : widget.module.buildPage,
          adaptivePageBuilder: widget.module.isAdaptive
              ? widget.module.buildAdaptivePage
              : null,
          pageWrapper: widget.module.pageWrapper,
        ),
      ),
    );
  }
}
