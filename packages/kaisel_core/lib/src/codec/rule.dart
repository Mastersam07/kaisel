/// Binds a [UrlPattern] to a route, giving a single URL ⇄ stack rule with both
/// directions declared together. Assembled into a codec in `route_codec`.
///
/// See `doc/design/codec-dsl.md`.
library;

import '../kaisel_route.dart';
import 'url_pattern.dart';

/// One URL ⇄ route rule: decode a URL into a main stack, or encode a leaf
/// route back into a URL. Build one fluently with
/// `pattern.to(Build).from(Match)`, or hand-write both directions with
/// [Rule.custom].
///
/// The route-family type [R] (e.g. your sealed `AppRoute`) is inferred from the
/// surrounding `RouteCodec<R>` rule list, so you never spell it on each rule.
class Rule<R extends KaiselRoute> {
  const Rule._(this.decode, this.encode);

  /// A rule with hand-written directions, for anything the combinators can't
  /// express. [decode] returns the main stack (or null); [encode] returns the
  /// URL for a leaf route it owns (or null).
  factory Rule.custom({
    required List<R>? Function(Uri uri) decode,
    required Uri? Function(R route) encode,
  }) => Rule<R>._(decode, encode);

  /// Decode [uri] into a main stack (breadcrumb + matched leaf), or null.
  final List<R>? Function(Uri uri) decode;

  /// Encode a leaf [route] to a URL, or null if this rule doesn't own it.
  final Uri? Function(R route) encode;
}

/// Start binding a [UrlPattern] to a route by naming its constructor; complete
/// with `.from`.
extension RuleBinding on UrlPattern {
  /// Build the route from this pattern's captures.
  PartialRule to(KaiselRoute Function(Captures captures) build) =>
      PartialRule._(this, build, const <KaiselRoute>[]);
}

/// A pattern bound to a constructor, awaiting its route → captures matcher.
/// Intentionally not generic in the route family: that keeps `.to`'s build from
/// pinning the type to the leaf, so the family is inferred at `.from`.
class PartialRule {
  const PartialRule._(this._pattern, this._build, this._breadcrumb);

  final UrlPattern _pattern;
  final KaiselRoute Function(Captures captures) _build;
  final List<KaiselRoute> _breadcrumb;

  /// Decode onto [breadcrumb] followed by the matched leaf, so a deep link
  /// restores a full back-stack. The breadcrumb is decode-side only.
  PartialRule under(List<KaiselRoute> breadcrumb) =>
      PartialRule._(_pattern, _build, breadcrumb);

  /// Complete with a route → captures matcher (null if the route isn't this
  /// rule's). The idiom is `(r) => r is Leaf ? r.props : null` — `props` order
  /// must match the pattern's capture order, verified by the codec's round-trip
  /// self-check at startup.
  Rule<R> from<R extends KaiselRoute>(List<Object?>? Function(R route) match) {
    final pattern = _pattern;
    final build = _build;
    final breadcrumb = _breadcrumb;
    return Rule<R>._(
      (uri) {
        final captures = pattern.parseUri(uri);
        if (captures == null) return null;
        return <R>[
          for (final b in breadcrumb) b as R,
          build(Captures(captures)) as R,
        ];
      },
      (route) {
        final captures = match(route);
        if (captures == null) return null;
        return pattern.printUri(captures);
      },
    );
  }
}

/// A no-capture rule: the fixed [route] at the fixed [pattern], optionally
/// decoded [under] a breadcrumb.
Rule<R> fixed<R extends KaiselRoute>(
  R route,
  UrlPattern pattern, {
  List<R> under = const <Never>[],
}) => Rule<R>._(
  (uri) => pattern.parseUri(uri) == null ? null : <R>[...under, route],
  (r) => r == route ? pattern.printUri(const <Object?>[]) : null,
);
