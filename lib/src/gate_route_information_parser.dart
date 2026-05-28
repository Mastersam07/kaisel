import 'package:flutter/widgets.dart';

import 'gate_codec.dart';
import 'gate_route.dart';

/// Parses incoming route information (URLs, deep links, restored state)
/// into a stack of routes for the delegate to render.
///
/// v0.1 always produces a single-route stack via [GateCodec.decode]. If
/// the URL is unrecognised, the stack falls back to [fallback].
class GateRouteInformationParser<R extends GateRoute>
    extends RouteInformationParser<List<R>> {
  /// Create a parser backed by [codec], falling back to [fallback] when
  /// the URL is unrecognised.
  GateRouteInformationParser({
    required this.codec,
    required this.fallback,
  });

  /// The route ↔ URL codec.
  final GateCodec<R> codec;

  /// Route used when [GateCodec.decode] returns `null`.
  final R fallback;

  @override
  Future<List<R>> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final decoded = codec.decode(routeInformation.uri);
    return [decoded ?? fallback];
  }

  @override
  RouteInformation? restoreRouteInformation(List<R> configuration) {
    if (configuration.isEmpty) return null;
    return RouteInformation(uri: codec.encode(configuration.last));
  }
}
