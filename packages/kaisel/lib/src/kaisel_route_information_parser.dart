import 'package:flutter/widgets.dart';
import 'package:kaisel_core/kaisel_core.dart';

/// Parses incoming route information (URLs, deep links, restored state)
/// into a [KaiselConfig] for the delegate to apply.
///
/// The configuration type is [KaiselConfig] so URLs can carry
/// nested-router state (a branched shell's branch+stack, or a mounted
/// module's stack) in addition to the main stack. Three ways to wire
/// the codec:
///
/// * **Stack-only URLs**: wrap your existing [KaiselStackCodec] via
///   `KaiselRouteInformationParser.fromStackCodec`.
/// * **Nested URLs**: write a [KaiselConfigCodec] that returns
///   [KaiselConfig] with a non-null `nestedState` (a [KaiselShellConfig]
///   or [KaiselModuleConfig]) for paths that address into the nested
///   router. The default constructor takes one of these.
/// * **Single-route URLs** (legacy [KaiselCodec]): use `.single`. The
///   parser internally wraps it in [KaiselSingleStackCodec] then
///   [StackToConfigCodec].
class KaiselRouteInformationParser<R extends KaiselRoute>
    extends RouteInformationParser<KaiselConfig<R>> {
  /// Create a parser backed by a [KaiselConfigCodec], which can address
  /// state inside a nested router (branched shell or module mount).
  ///
  /// On an unrecognised URL the parser yields a [KaiselConfig] with
  /// `mainStack: fallback` and no nested state.
  KaiselRouteInformationParser({
    required KaiselConfigCodec<R> codec,
    required List<R> fallback,
  }) : _codec = codec,
       _fallback = List<R>.unmodifiable(fallback),
       assert(
         fallback.isNotEmpty,
         'fallback stack must contain at least one route',
       );

  /// Accept a [KaiselStackCodec] and treat URLs as stack-only (no shell
  /// state ever round-trips through the URL).
  KaiselRouteInformationParser.fromStackCodec({
    required KaiselStackCodec<R> codec,
    required List<R> fallback,
  }) : this(codec: StackToConfigCodec<R>(codec), fallback: fallback);

  /// Create a parser backed by a single-route [KaiselCodec]. Equivalent
  /// to wrapping it in [KaiselSingleStackCodec] then [StackToConfigCodec].
  KaiselRouteInformationParser.single({
    required KaiselCodec<R> codec,
    required R fallback,
  }) : this(
         codec: StackToConfigCodec<R>(KaiselSingleStackCodec<R>(codec)),
         fallback: [fallback],
       );

  final KaiselConfigCodec<R> _codec;
  final List<R> _fallback;

  /// The active config codec.
  KaiselConfigCodec<R> get codec => _codec;

  /// The fallback stack used when [KaiselConfigCodec.decode] returns
  /// `null`.
  List<R> get fallback => _fallback;

  @override
  Future<KaiselConfig<R>> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final decoded = _codec.decode(routeInformation.uri);
    if (decoded == null) return KaiselConfig<R>(mainStack: _fallback);
    return decoded;
  }

  @override
  RouteInformation? restoreRouteInformation(KaiselConfig<R> configuration) {
    if (configuration.mainStack.isEmpty) return null;
    return RouteInformation(uri: _codec.encode(configuration));
  }
}
