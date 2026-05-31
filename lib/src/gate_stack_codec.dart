import 'gate_codec.dart';
import 'gate_route.dart';

/// Maps URLs to and from full route stacks.
///
/// Unlike [GateCodec] (which handles one URL ↔ one route), a
/// `GateStackCodec` can decode a URL into a stack of more than one
/// frame. This lets you give back-navigation sensible behaviour on
/// deep links: `/products/sku-42` can decode to `[Home, ProductDetail('sku-42')]`
/// so the back button goes home instead of exiting the app.
///
/// Convention: [encode] typically encodes the destination (top of the
/// stack); intermediate routes are implicit in the URL's hierarchy.
/// Two stacks ending in the same route encode to the same URL.
///
/// ```dart
/// class AppStackCodec implements GateStackCodec<AppRoute> {
///   const AppStackCodec();
///
///   @override
///   Uri encode(List<AppRoute> stack) => switch (stack.last) {
///         Home() => Uri(path: '/'),
///         ProductDetail(:final id) => Uri(path: '/products/$id'),
///         Settings() => Uri(path: '/settings'),
///       };
///
///   @override
///   List<AppRoute>? decode(Uri uri) => switch (uri.pathSegments) {
///         [] || [''] => const [Home()],
///         ['products', final id] => [const Home(), ProductDetail(id)],
///         ['settings'] => const [Home(), Settings()],
///         _ => null,
///       };
/// }
/// ```
abstract class GateStackCodec<R extends GateRoute> {
  /// Const constructor so subclasses can be `const`.
  const GateStackCodec();

  /// Encode a stack to a URL.
  Uri encode(List<R> stack);

  /// Decode a URL to a stack. Return `null` if the URL is unrecognised
  /// — the parser will fall back to the configured fallback stack.
  List<R>? decode(Uri uri);
}

/// Adapts a single-route [GateCodec] (v0.1 / v0.2) to the multi-route
/// [GateStackCodec] interface. Useful for migrating without rewriting
/// your codec.
class GateSingleStackCodec<R extends GateRoute> implements GateStackCodec<R> {
  /// Wrap [codec] so it can be used wherever a [GateStackCodec] is
  /// expected. Encodes the top of the stack; decodes to a depth-1 stack.
  const GateSingleStackCodec(this.codec);

  /// The wrapped single-route codec.
  final GateCodec<R> codec;

  @override
  Uri encode(List<R> stack) => codec.encode(stack.last);

  @override
  List<R>? decode(Uri uri) {
    final route = codec.decode(uri);
    return route == null ? null : [route];
  }
}
