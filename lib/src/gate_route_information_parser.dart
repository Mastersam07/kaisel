import 'package:flutter/widgets.dart';

import 'gate_codec.dart';
import 'gate_config.dart';
import 'gate_route.dart';
import 'gate_stack_codec.dart';

/// Parses incoming route information (URLs, deep links, restored state)
/// into a [GateConfig] for the delegate to apply.
///
/// In v0.5+ the configuration type is [GateConfig] so URLs can carry
/// nested-router state (a branched shell's branch+stack, or a mounted
/// module's stack) in addition to the main stack. Migration paths:
///
/// * **Stack-only URLs** (the v0.4 default): wrap your existing
///   [GateStackCodec] via `GateRouteInformationParser.fromStackCodec`.
/// * **Nested URLs**: write a [GateConfigCodec] that returns
///   [GateConfig] with a non-null `nestedState` (a [GateShellConfig]
///   or [GateModuleConfig]) for paths that address into the nested
///   router. The default constructor takes one of these.
/// * **Single-route URLs** (legacy [GateCodec]): use `.single`. The
///   parser internally wraps it in [GateSingleStackCodec] then
///   [StackToConfigCodec].
class GateRouteInformationParser<R extends GateRoute>
    extends RouteInformationParser<GateConfig<R>> {
  /// Create a parser backed by a [GateConfigCodec], which can address
  /// state inside a nested router (branched shell or module mount).
  ///
  /// On an unrecognised URL the parser yields a [GateConfig] with
  /// `mainStack: fallback` and no nested state.
  GateRouteInformationParser({
    required GateConfigCodec<R> codec,
    required List<R> fallback,
  })  : _codec = codec,
        _fallback = List<R>.unmodifiable(fallback),
        assert(
          fallback.isNotEmpty,
          'fallback stack must contain at least one route',
        );

  /// Migration helper: accept a v0.4 [GateStackCodec] and treat URLs
  /// as stack-only (no shell state ever round-trips through the URL).
  GateRouteInformationParser.fromStackCodec({
    required GateStackCodec<R> codec,
    required List<R> fallback,
  }) : this(codec: StackToConfigCodec<R>(codec), fallback: fallback);

  /// Create a parser backed by a single-route [GateCodec]. Equivalent
  /// to wrapping it in [GateSingleStackCodec] then [StackToConfigCodec].
  GateRouteInformationParser.single({
    required GateCodec<R> codec,
    required R fallback,
  }) : this(
          codec: StackToConfigCodec<R>(GateSingleStackCodec<R>(codec)),
          fallback: [fallback],
        );

  final GateConfigCodec<R> _codec;
  final List<R> _fallback;

  /// The active config codec.
  GateConfigCodec<R> get codec => _codec;

  /// The fallback stack used when [GateConfigCodec.decode] returns
  /// `null`.
  List<R> get fallback => _fallback;

  @override
  Future<GateConfig<R>> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final decoded = _codec.decode(routeInformation.uri);
    if (decoded == null) return GateConfig<R>(mainStack: _fallback);
    return decoded;
  }

  @override
  RouteInformation? restoreRouteInformation(GateConfig<R> configuration) {
    if (configuration.mainStack.isEmpty) return null;
    return RouteInformation(uri: _codec.encode(configuration));
  }
}
