import 'package:flutter/widgets.dart';
import 'package:kaisel_core/kaisel_core.dart';

import 'kaisel_adaptive.dart';
import 'kaisel_page_wrapper.dart';
import 'kaisel_route_information_parser.dart';
import 'kaisel_router_delegate.dart';
import 'kaisel_stack_restorer.dart';

/// A ready-made [RouterConfig] that bundles a [KaiselRouter] and a
/// [KaiselRouterDelegate] — plus a URL parser and platform provider when you
/// supply a [KaiselConfigCodec] — into the single object that
/// `MaterialApp.router(routerConfig:)` expects. The same shape go_router uses.
///
/// This is the convenience layer over the explicit pieces: you keep your own
/// `MaterialApp` (theme, localizations, …), and the router plumbing collapses
/// to one value:
///
/// ```dart
/// final _config = KaiselRouterConfig<AppRoute>(
///   initial: const Home(),
///   builder: (context, route) => switch (route) {
///     Home() => const HomeScreen(),
///     ProductDetail(:final id) => ProductDetailScreen(id: id),
///   },
/// );
///
/// // in build:
/// MaterialApp.router(routerConfig: _config, theme: myTheme);
/// ```
///
/// Omit [codec] for a URL-less app (the config runs delegate-only). Pass a
/// [codec] (and optional [fallback]) for a URL-addressable one; the parser and
/// a [PlatformRouteInformationProvider] are wired for you.
///
/// Hold it as a top-level `final` for an app-lifetime router — no disposal
/// needed, exactly like `final _router = GoRouter(...)`. Call [dispose] only if
/// you own its lifecycle in a [State].
class KaiselRouterConfig<R extends KaiselRoute>
    extends RouterConfig<KaiselConfig<R>> {
  KaiselRouterConfig._({
    required this.router,
    required KaiselRouterDelegate<R> delegate,
    required RouteInformationParser<KaiselConfig<R>>? parser,
    required RouteInformationProvider? provider,
  }) : _delegate = delegate,
       _provider = provider,
       super(
         routerDelegate: delegate,
         routeInformationParser: parser,
         routeInformationProvider: provider,
         backButtonDispatcher: RootBackButtonDispatcher(),
       );

  /// Assemble a config from the parts you actually care about.
  factory KaiselRouterConfig({
    required R initial,
    required KaiselPageBuilder<R> builder,
    List<KaiselGuard<R>> guards = const [],
    KaiselPageWrapper<R>? pageWrapper,
    KaiselModalBuilder? modalBuilder,
    KaiselObserversBuilder? observers,
    KaiselConfigCodec<R>? codec,
    String? restorationScopeId,
    KaiselRouteRestorer<R>? restoreRoute,
    List<R>? fallback,
  }) {
    final router = KaiselRouter<R>(initial: initial, guards: guards);
    return _assemble<R>(
      router: router,
      delegate: KaiselRouterDelegate<R>(
        router: router,
        builder: builder,
        pageWrapper: pageWrapper,
        modalBuilder: modalBuilder,
        observers: observers,
        restorationScopeId: restorationScopeId,
        restoreRoute: restoreRoute,
        codec: codec,
      ),
      codec: codec,
      fallback: fallback ?? [initial],
    );
  }

  /// Like the default constructor, but with an adaptive page [builder] (the
  /// builder receives a [KaiselStackContext] per entry so it can return a
  /// [KaiselAbsorbingPage] to collapse master-detail at wide breakpoints).
  factory KaiselRouterConfig.adaptive({
    required R initial,
    required KaiselAdaptivePageBuilder<R> builder,
    List<KaiselGuard<R>> guards = const [],
    KaiselPageWrapper<R>? pageWrapper,
    KaiselModalBuilder? modalBuilder,
    KaiselObserversBuilder? observers,
    KaiselConfigCodec<R>? codec,
    String? restorationScopeId,
    KaiselRouteRestorer<R>? restoreRoute,
    List<R>? fallback,
  }) {
    final router = KaiselRouter<R>(initial: initial, guards: guards);
    return _assemble<R>(
      router: router,
      delegate: KaiselRouterDelegate<R>.adaptive(
        router: router,
        builder: builder,
        pageWrapper: pageWrapper,
        modalBuilder: modalBuilder,
        observers: observers,
        restorationScopeId: restorationScopeId,
        restoreRoute: restoreRoute,
        codec: codec,
      ),
      codec: codec,
      fallback: fallback ?? [initial],
    );
  }

  // Wires the optional URL parser + platform provider and builds the config.
  static KaiselRouterConfig<R> _assemble<R extends KaiselRoute>({
    required KaiselRouter<R> router,
    required KaiselRouterDelegate<R> delegate,
    required KaiselConfigCodec<R>? codec,
    required List<R> fallback,
  }) {
    RouteInformationParser<KaiselConfig<R>>? parser;
    RouteInformationProvider? provider;
    if (codec case final codec?) {
      parser = KaiselRouteInformationParser<R>(
        codec: codec,
        fallback: fallback,
      );
      provider = PlatformRouteInformationProvider(
        initialRouteInformation: RouteInformation(
          uri: Uri.parse(
            WidgetsBinding.instance.platformDispatcher.defaultRouteName,
          ),
        ),
      );
    }
    return KaiselRouterConfig<R>._(
      router: router,
      delegate: delegate,
      parser: parser,
      provider: provider,
    );
  }

  /// The bundled router, for imperative navigation outside the widget tree.
  final KaiselRouter<R> router;

  final KaiselRouterDelegate<R> _delegate;
  final RouteInformationProvider? _provider;

  /// Dispose the bundled router, delegate, and (if any) provider. Only needed
  /// when you don't keep the config for the app's lifetime.
  void dispose() {
    _delegate.dispose();
    router.dispose();
    final provider = _provider;
    if (provider is PlatformRouteInformationProvider) provider.dispose();
  }
}
