import 'kaisel_route.dart';

/// Bidirectional mapping between a route and a URL.
///
/// The codec is the **only** load-bearing connection between your typed
/// route stack and the URL bar / deep links. Routes are defined in terms
/// of your sealed types; URLs are a separate projection of those types,
/// implemented here.
///
/// This is the legacy single-route codec: it maps the top of the stack
/// to a URL and back. For deep links that restore a multi-frame stack
/// (e.g. `/products/42/reviews/new` → `[Home, Product, Reviews]`), use
/// [KaiselStackCodec] instead.
///
/// Example:
///
/// ```dart
/// class AppCodec implements KaiselCodec<AppRoute> {
///   @override
///   Uri encode(AppRoute route) => switch (route) {
///     Home() => Uri(path: '/'),
///     ProductDetail(:final id) => Uri(path: '/products/$id'),
///   };
///
///   @override
///   AppRoute? decode(Uri uri) {
///     final segments = uri.pathSegments;
///     return switch (segments) {
///       [] || [''] => const Home(),
///       ['products', final id] => ProductDetail(id),
///       _ => null,
///     };
///   }
/// }
/// ```
///
/// If you don't need URL routing (mobile-only, no deep links, no state
/// restoration via URLs), don't implement this — just don't pass an
/// information parser when wiring the router.
abstract interface class KaiselCodec<R extends KaiselRoute> {
  /// Encode a route into a URL for the browser bar / restoration.
  Uri encode(R route);

  /// Decode a URL into a route. Return `null` for unrecognised URLs;
  /// the parser will fall back to the route you specify.
  R? decode(Uri uri);
}
