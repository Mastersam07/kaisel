import 'package:flutter/widgets.dart';

import 'gate_route.dart';

/// Optional signature for customising how a route becomes a [Page].
///
/// Defaults to wrapping in a [MaterialPage]. Override to use
/// [CupertinoPage], custom transitions, or fullscreen-dialog routes.
///
/// The wrapper receives a [GatePageWrapperContext] with the route,
/// child widget, page key, and stack context (position, previous
/// route, etc.). Pattern-match on `(ctx.route, ctx.previous)` to
/// pick transitions based on the route pair, not just the
/// destination.
typedef GatePageWrapper<R extends GateRoute> =
    Page<Object?> Function(GatePageWrapperContext<R> ctx);

/// Context passed to a [GatePageWrapper]. Carries the bits the
/// wrapper needs to decide how to wrap and animate the page.
///
/// Most useful field is [previous]: the route below this page on
/// the rendered stack. With pattern matching you can pick a
/// transition based on the route pair:
///
/// ```dart
/// pageWrapper: (ctx) {
///   return switch ((ctx.previous, ctx.route)) {
///     (ProductList(), ProductDetail()) =>
///       _ZoomPage(key: ctx.key, child: ctx.child),
///     (_, Settings()) =>
///       _SlideUpPage(key: ctx.key, child: ctx.child),
///     _ => MaterialPage(key: ctx.key, child: ctx.child),
///   };
/// }
/// ```
///
/// The Navigator handles push/pop direction automatically based on
/// pages-list diff. The wrapper picks the *style* of transition
/// (which [Page] subclass to construct); the framework picks the
/// direction (run forward on add, reverse on remove).
@immutable
class GatePageWrapperContext<R extends GateRoute> {
  /// Build a wrapper context. Internal to the framework. User code
  /// receives instances of this type; it doesn't construct them.
  const GatePageWrapperContext({
    required this.route,
    required this.child,
    required this.key,
    required this.position,
    required this.stackLength,
    this.previous,
  });

  /// The route this page represents.
  final R route;

  /// The widget produced by the page builder for [route].
  final Widget child;

  /// The local key the framework wants for this page's identity.
  /// Pass this to whatever [Page] subclass you construct.
  final LocalKey key;

  /// This page's position in the rendered pages list. Zero at the
  /// bottom of the stack; `stackLength - 1` at the top.
  final int position;

  /// Total number of pages in the rendered stack. With absorbing
  /// pages this can be less than `router.depth`.
  final int stackLength;

  /// The route of the page immediately below this one in the
  /// rendered stack, or null at the bottom. Use this to
  /// pattern-match on the route pair for transitions that care
  /// where you came from.
  ///
  /// For absorbing pages, "below" refers to the rendered Navigator's
  /// list, not the router's full stack. If page B at rendered
  /// position 1 absorbs entries below it on the router's stack, the
  /// page at rendered position 2 above it sees [previous] = B's
  /// route, not the absorbed entries.
  final R? previous;

  /// Whether this is the topmost page in the rendered stack.
  bool get isTop => position == stackLength - 1;

  /// Whether this is the bottom page in the rendered stack.
  bool get isBottom => position == 0;
}
