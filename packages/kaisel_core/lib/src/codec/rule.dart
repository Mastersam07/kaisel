/// Binds a [UrlPattern] to a route, giving a single URL ⇄ config rule with both
/// directions declared together. Assembled into a codec in `route_codec`, and
/// composed into shells/modules in `nested`.
///
/// See `doc/design/codec-dsl.md`.
library;

import '../kaisel_config.dart';
import '../kaisel_route.dart';
import 'url_pattern.dart';

/// One URL ⇄ config rule: decode a URL into a [KaiselConfig] (main stack plus
/// any nested shell/module state), or encode a config back into a URL. Build
/// one fluently with `pattern.to(Build).from(Match)`, or hand-write both
/// directions with [Rule.custom].
///
/// The route-family type [R] is inferred from the surrounding `RouteCodec<R>`
/// rule list, so you never spell it on each rule.
class Rule<R extends KaiselRoute> {
  const Rule._(this.decode, this.encode);

  /// A rule with hand-written directions, for anything the combinators can't
  /// express. [decode] returns a config (or null); [encode] returns the URL for
  /// a config it owns (or null).
  factory Rule.custom({
    required KaiselConfig<R>? Function(Uri uri) decode,
    required Uri? Function(KaiselConfig<R> config) encode,
  }) => Rule<R>._(decode, encode);

  /// Decode [uri] into a config, or null if this rule doesn't match.
  final KaiselConfig<R>? Function(Uri uri) decode;

  /// Encode [config] to a URL, or null if this rule doesn't own it.
  final Uri? Function(KaiselConfig<R> config) encode;
}

/// Start binding a [UrlPattern] to a route by naming its constructor; complete
/// with `.from`.
extension RuleBinding on UrlPattern {
  /// Build the route from this pattern's captures.
  PartialRule to(KaiselRoute Function(Captures captures) build) =>
      PartialRule._(this, build, const <KaiselRoute>[]);
}

/// A pattern bound to a constructor, awaiting its route → captures matcher.
/// Not generic in the family so `.to`'s build doesn't pin the type to the leaf;
/// the family is inferred at `.from`.
class PartialRule {
  const PartialRule._(this._pattern, this._build, this._breadcrumb);

  final UrlPattern _pattern;
  final KaiselRoute Function(Captures captures) _build;
  final List<KaiselRoute> _breadcrumb;

  /// Decode onto [breadcrumb] followed by the matched leaf, so a deep link
  /// restores a full back-stack. The breadcrumb is decode-side only.
  PartialRule under(List<KaiselRoute> breadcrumb) =>
      PartialRule._(_pattern, _build, breadcrumb);

  /// Complete with a route → captures matcher (null if not this rule's). The
  /// idiom is `(r) => r is Leaf ? r.props : null`; `props` order must match the
  /// pattern's capture order, verified by the codec's round-trip self-check.
  Rule<R> from<R extends KaiselRoute>(List<Object?>? Function(R route) match) {
    final pattern = _pattern;
    final build = _build;
    final breadcrumb = _breadcrumb;
    return Rule<R>._(
      (uri) {
        final captures = pattern.parseUri(uri);
        if (captures == null) return null;
        return KaiselConfig<R>(
          mainStack: <R>[
            for (final b in breadcrumb) b as R,
            build(Captures(captures)) as R,
          ],
        );
      },
      (config) {
        if (config.nestedState != null) return null;
        final captures = match(config.mainStack.last);
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
  (uri) => pattern.parseUri(uri) == null
      ? null
      : KaiselConfig<R>(mainStack: <R>[...under, route]),
  (config) => config.nestedState == null && config.mainStack.last == route
      ? pattern.printUri(const <Object?>[])
      : null,
);
