import 'package:flutter/material.dart';

import 'gate_route.dart';

/// The result of building a page for one stack entry in an adaptive
/// page builder.
///
/// Most pages are [GateStandalonePage]: one stack entry produces one
/// visible page, the default 1:1 model. [GateAbsorbingPage] lets a
/// route render a widget that ALSO subsumes one or more entries
/// below it on the stack. Used for master-detail layouts where, at
/// wide breakpoints, the detail visually contains the list.
sealed class GatePageResult {
  /// Const constructor so subclasses can be `const`.
  const GatePageResult();

  /// The widget this result will display.
  Widget get widget;
}

/// A standalone page: this entry produces one visible page,
/// unchanged from the default 1:1 stack-to-pages mapping.
class GateStandalonePage extends GatePageResult {
  /// Wrap [widget] as a standalone page.
  const GateStandalonePage(this.widget);

  @override
  final Widget widget;
}

/// A page that subsumes [absorbing] entries below it on the stack.
/// The renderer skips those entries; they don't get their own page.
///
/// Typical use: master-detail at a wide breakpoint, where the
/// detail route absorbs the master.
///
/// ```dart
/// switch ((route, stack.previous, MediaQuery.sizeOf(context).width)) {
///   (ProductDetail(:final id), ProductList(:final category), var w)
///       when w >= 700 => GateAbsorbingPage(
///         widget: GateMasterDetailScaffold(
///           master: ProductListScreen(category: category),
///           detail: ProductDetailScreen(id: id),
///         ),
///         absorbing: 1,
///       ),
///   (ProductDetail(:final id), _, _) =>
///       GateStandalonePage(ProductDetailScreen(id: id)),
///   // ...
/// }
/// ```
///
/// Page identity for the rendered page is keyed on the *lowest*
/// absorbed entry. That way, transitioning between
/// `[List, DetailA]` and `[List, DetailB]` (a typical master-detail
/// selection) preserves Navigator identity. The child widget swaps
/// without a Navigator-level animation. Wrap the swapping content
/// in an [AnimatedSwitcher] if you want a fade between details.
///
/// Popping a Navigator page that came from a [GateAbsorbingPage]
/// pops the absorbing (topmost) entry, not the lowest absorbed one.
/// `[List, Detail]` absorbed and then popped becomes `[List]`, just
/// as if the page had been standalone.
class GateAbsorbingPage extends GatePageResult {
  /// Wrap [widget] as an absorbing page that consumes [absorbing]
  /// entries below it on the stack.
  const GateAbsorbingPage({
    required this.widget,
    this.absorbing = 1,
  }) : assert(absorbing >= 1, 'absorbing must be at least 1');

  @override
  final Widget widget;

  /// How many entries below this one to absorb. Defaults to 1 (the
  /// canonical master-detail case).
  final int absorbing;
}

/// Context provided to an adaptive page builder for a given stack
/// entry. Surfaces the full stack and the entry's position so the
/// builder can pattern-match on what's above or below before
/// deciding whether to render a standalone or absorbing page.
@immutable
class GateStackContext<R extends GateRoute> {
  /// Create a context for an entry at [position] within [stack].
  const GateStackContext({
    required this.stack,
    required this.position,
  })  : assert(stack.length > 0, 'stack must be non-empty'),
        assert(position >= 0, 'position must be non-negative'),
        assert(position < stack.length, 'position out of range');

  /// The full stack as the router currently has it. Read-only.
  final List<R> stack;

  /// This entry's index within [stack]. The bottom entry is 0; the
  /// top is `stack.length - 1`.
  final int position;

  /// The entry directly below this one, or `null` if this is at the
  /// bottom of the stack.
  R? get previous => position > 0 ? stack[position - 1] : null;

  /// The entry directly above this one, or `null` if this is at the
  /// top of the stack.
  R? get next => position < stack.length - 1 ? stack[position + 1] : null;

  /// Whether this entry is the topmost in the stack.
  bool get isTop => position == stack.length - 1;

  /// Whether this entry is at the bottom of the stack.
  bool get isBottom => position == 0;
}

/// Signature for an adaptive page builder.
///
/// Unlike [GatePageBuilder], this receives a [GateStackContext] so
/// the builder can pattern-match on neighbours and decide whether
/// to render a standalone page or an absorbing one that consumes
/// entries below.
///
/// See [GateRouterDelegate.adaptive] for how to wire one up.
typedef GateAdaptivePageBuilder<R extends GateRoute> = GatePageResult Function(
  BuildContext context,
  R route,
  GateStackContext<R> stack,
);

/// Convenience widget for master-detail layouts.
///
/// Renders [master] and [detail] side by side with an optional
/// divider between them. Use inside a [GateAbsorbingPage]'s widget
/// to lay out the absorbed master and the absorbing detail.
///
/// This is purely a convenience; replace with your own layout if
/// you need different breakpoints, ratios, or chrome.
class GateMasterDetailScaffold extends StatelessWidget {
  /// Lay [master] and [detail] side by side.
  const GateMasterDetailScaffold({
    super.key,
    required this.master,
    required this.detail,
    this.masterFraction = 0.33,
    this.divider,
  }) : assert(
          masterFraction > 0 && masterFraction < 1,
          'masterFraction must be between 0 and 1 exclusive',
        );

  /// The master pane (typically a list).
  final Widget master;

  /// The detail pane (typically the selected item's screen).
  final Widget detail;

  /// Fraction of horizontal space given to [master]. Defaults to 1/3.
  final double masterFraction;

  /// Optional divider between the two panes. Defaults to a
  /// [VerticalDivider] with width 1.
  final Widget? divider;

  @override
  Widget build(BuildContext context) {
    final masterFlex = (masterFraction * 1000).round();
    final detailFlex = 1000 - masterFlex;
    return Row(
      children: [
        Expanded(flex: masterFlex, child: master),
        divider ?? const VerticalDivider(width: 1),
        Expanded(flex: detailFlex, child: detail),
      ],
    );
  }
}
