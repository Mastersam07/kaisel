import 'package:flutter/widgets.dart';
import 'package:gate_core/gate_core.dart';

/// An [InheritedWidget] the framework injects around each rendered
/// page's child, exposing navigational context to descendant
/// widgets.
///
/// Descendants call [GatePageScope.of] or [GatePageScope.maybeOf] to
/// read the route they're rendering for, their page's position in
/// the rendered stack, the route below it, and convenience getters
/// for `isTop` / `isBottom`. Useful for:
///
/// - Showing a back arrow only when there's actually a page below
///   to pop to. With absorbing pages, `isBottom` distinguishes
///   "I'm the only rendered page" (don't show back) from "I'm
///   stacked on top of something" (do show back).
/// - Pattern-matching on `previous` in a deeply nested widget
///   without prop-drilling.
/// - Customising AppBar / chrome based on `isTop` or `position`.
///
/// The scope's `route` is typed as [GateRoute] (the base class).
/// Descendants pattern-match on the actual variant:
///
/// ```dart
/// final scope = GatePageScope.of(context);
/// switch (scope.route) {
///   case BookDetail(:final id): ...;
///   case BookList(): ...;
/// }
/// ```
///
/// The scope is injected at every wrap call site (the main
/// delegate's simple and adaptive paths, and the inner navigator's
/// simple and adaptive paths). Custom page wrappers receive the
/// child already wrapped in `GatePageScope` via
/// `GatePageWrapperContext.child`, so a wrapper that does
/// `Page(child: ctx.child)` automatically propagates the scope into
/// the page's content.
@immutable
class GatePageScope extends InheritedWidget {
  /// Build a page scope. Internal to the framework. User code reads
  /// scopes via [of] / [maybeOf]; it doesn't construct them.
  const GatePageScope({
    super.key,
    required this.route,
    required this.position,
    required this.stackLength,
    this.previous,
    required super.child,
  });

  /// The route this page represents.
  final GateRoute route;

  /// This page's position in the rendered pages list. Zero at the
  /// bottom of the stack; `stackLength - 1` at the top.
  final int position;

  /// Total number of pages in the rendered stack. With absorbing
  /// pages this can be less than `router.depth`.
  final int stackLength;

  /// The route of the page immediately below this one in the
  /// rendered stack, or null at the bottom.
  ///
  /// For absorbing pages, "below" refers to the rendered Navigator's
  /// list, not the router's full stack. If page B at rendered
  /// position 1 absorbs entries below it on the router's stack, the
  /// page at rendered position 2 above it sees [previous] = B's
  /// route, not the absorbed entries.
  final GateRoute? previous;

  /// Whether this page is the topmost in the rendered stack.
  bool get isTop => position == stackLength - 1;

  /// Whether this page is the bottom of the rendered stack.
  ///
  /// True means there's no page below to pop back to. With
  /// absorbing pages, a route can collapse the entries below it
  /// into its own page, making the rendered stack shorter than the
  /// router's stack. A widget that wants to hide a back arrow when
  /// it's the only page on screen (e.g., the detail panel of a
  /// master-detail scaffold absorbed at wide widths) should key off
  /// this getter rather than guessing from the route.
  bool get isBottom => position == 0;

  /// Look up the nearest enclosing [GatePageScope] above [context],
  /// or null if there isn't one.
  ///
  /// Returns null if [context] isn't a descendant of a gate-managed
  /// page (e.g., a widget outside the router's Navigator subtrees,
  /// or in a test harness that doesn't pump the framework).
  static GatePageScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GatePageScope>();

  /// Like [maybeOf] but throws if there's no enclosing scope.
  ///
  /// Use this from widgets that are always rendered inside a
  /// gate-managed page. Use [maybeOf] when the widget might be
  /// rendered outside one (e.g., a shared widget you also use in
  /// `showDialog`).
  static GatePageScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(
      scope != null,
      'GatePageScope.of() called from a context without a '
      'GatePageScope ancestor. Either use GatePageScope.maybeOf(), '
      'or ensure the calling widget is rendered inside a page '
      'built by gate.',
    );
    return scope!;
  }

  @override
  bool updateShouldNotify(GatePageScope oldWidget) =>
      route != oldWidget.route ||
      position != oldWidget.position ||
      stackLength != oldWidget.stackLength ||
      previous != oldWidget.previous;
}
