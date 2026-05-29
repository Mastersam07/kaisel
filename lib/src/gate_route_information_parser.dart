import 'package:flutter/widgets.dart';

import 'gate_codec.dart';
import 'gate_route.dart';
import 'gate_stack_codec.dart';

/// Parses incoming route information (URLs, deep links, restored state)
/// into a stack of routes for the delegate to render.
///
/// Accepts either a [GateStackCodec] (multi-route, recommended) or a
/// single-route [GateCodec] (legacy convenience). With a stack codec, a
/// single URL can decode into multiple frames so the back button has
/// somewhere sensible to go on deep links.
class GateRouteInformationParser<R extends GateRoute>
    extends RouteInformationParser<List<R>> {
  /// Create a parser backed by a multi-route [GateStackCodec].
  ///
  /// On an unrecognised URL the parser yields [fallback].
  GateRouteInformationParser({
    required GateStackCodec<R> codec,
    required List<R> fallback,
  })  : _codec = codec,
        _fallback = List<R>.unmodifiable(fallback),
        assert(
          fallback.isNotEmpty,
          'fallback stack must contain at least one route',
        );

  /// Create a parser backed by a single-route [GateCodec]. Equivalent
  /// to wrapping it in [GateSingleStackCodec] manually.
  GateRouteInformationParser.single({
    required GateCodec<R> codec,
    required R fallback,
  })  : _codec = GateSingleStackCodec<R>(codec),
        _fallback = List<R>.unmodifiable([fallback]);

  final GateStackCodec<R> _codec;
  final List<R> _fallback;

  /// The active stack codec.
  GateStackCodec<R> get codec => _codec;

  /// The fallback stack used when [GateStackCodec.decode] returns `null`.
  List<R> get fallback => _fallback;

  @override
  Future<List<R>> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final decoded = _codec.decode(routeInformation.uri);
    if (decoded == null || decoded.isEmpty) return _fallback;
    return decoded;
  }

  @override
  RouteInformation? restoreRouteInformation(List<R> configuration) {
    if (configuration.isEmpty) return null;
    return RouteInformation(uri: _codec.encode(configuration));
  }
}
