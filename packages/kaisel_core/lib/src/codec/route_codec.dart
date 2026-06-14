/// Assembles a list of [Rule]s into a [KaiselConfigCodec], dispatching both
/// directions over one ordered rule list so encode and decode can't drift.
library;

import '../kaisel_config.dart';
import '../kaisel_route.dart';
import 'rule.dart';

/// A `KaiselConfigCodec` built from declarative [Rule]s.
///
/// `decode` tries each rule in order and returns the first match (or the
/// [fallback]); `encode` tries each rule's matcher on the stack's leaf and
/// returns the first URL it produces. Because both directions walk the *same*
/// ordered list, an `encode` and `decode` can't disagree about which rule owns
/// a route — the class of "encoded URL decodes elsewhere" bug is removed.
class RouteCodec<R extends KaiselRoute> extends KaiselConfigCodec<R> {
  /// Build a codec from [rules], with an optional [fallback] for URLs no rule
  /// decodes.
  RouteCodec({required List<Rule<R>> rules, this.fallback})
    : _rules = List<Rule<R>>.of(rules);

  final List<Rule<R>> _rules;

  /// Decode result for a URL no rule matched (null → the router's own
  /// fallback applies).
  final List<R> Function(Uri uri)? fallback;

  @override
  KaiselConfig<R>? decode(Uri uri) {
    for (final rule in _rules) {
      final config = rule.decode(uri);
      if (config != null) return config;
    }
    final fb = fallback?.call(uri);
    return fb == null ? null : KaiselConfig<R>(mainStack: fb);
  }

  @override
  Uri encode(KaiselConfig<R> config) {
    for (final rule in _rules) {
      final uri = rule.encode(config);
      if (uri != null) return uri;
    }
    // No rule owns this config — fall back to the index path. A complete codec
    // has a rule for every route; `debugAssertRoundTrips` surfaces the gap.
    return Uri(path: '/');
  }

  /// Round-trip check for tests: every route in [routes] must survive
  /// `decode(encode(...))` back to itself. Throws on the first that doesn't —
  /// catching the encode/decode-drift class at test time rather than in
  /// production.
  void debugAssertRoundTrips(Iterable<R> routes) {
    for (final route in routes) {
      final uri = encode(KaiselConfig<R>(mainStack: <R>[route]));
      final leaf = decode(uri)?.mainStack.last;
      if (leaf != route) {
        throw StateError(
          'codec round-trip failed: $route encoded to "$uri" but decoded to '
          '${leaf ?? 'no match'}',
        );
      }
    }
  }
}
