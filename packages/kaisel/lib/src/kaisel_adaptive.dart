import 'package:flutter/material.dart';
import 'package:kaisel_core/framework.dart';

import 'kaisel_page_scope.dart';
import 'kaisel_page_wrapper.dart';

/// The result of building a page for one stack entry in an adaptive
/// page builder.
///
/// Most pages are [KaiselStandalonePage]: one stack entry produces one
/// visible page, the default 1:1 model. [KaiselAbsorbingPage] lets a
/// route render a widget that ALSO subsumes one or more entries
/// below it on the stack. Used for master-detail layouts where, at
/// wide breakpoints, the detail visually contains the list.
sealed class KaiselPageResult {
  /// Const constructor so subclasses can be `const`.
  const KaiselPageResult();

  /// The widget this result will display.
  Widget get widget;
}

/// A standalone page: this entry produces one visible page,
/// unchanged from the default 1:1 stack-to-pages mapping.
class KaiselStandalonePage extends KaiselPageResult {
  /// Wrap [widget] as a standalone page.
  const KaiselStandalonePage(this.widget);

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
///       when w >= 700 => KaiselAbsorbingPage(
///         widget: KaiselMasterDetailScaffold(
///           master: ProductListScreen(category: category),
///           detail: ProductDetailScreen(id: id),
///         ),
///         absorbing: 1,
///       ),
///   (ProductDetail(:final id), _, _) =>
///       KaiselStandalonePage(ProductDetailScreen(id: id)),
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
/// Popping a Navigator page that came from a [KaiselAbsorbingPage]
/// pops the absorbing (topmost) entry, not the lowest absorbed one.
/// `[List, Detail]` absorbed and then popped becomes `[List]`, just
/// as if the page had been standalone.
class KaiselAbsorbingPage extends KaiselPageResult {
  /// Wrap [widget] as an absorbing page that consumes [absorbing]
  /// entries below it on the stack.
  const KaiselAbsorbingPage({required this.widget, this.absorbing = 1})
    : assert(absorbing >= 1, 'absorbing must be at least 1');

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
class KaiselStackContext<R extends KaiselRoute> {
  /// Create a context for an entry at [position] within [stack].
  const KaiselStackContext({required this.stack, required this.position})
    : assert(stack.length > 0, 'stack must be non-empty'),
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
/// Unlike [KaiselPageBuilder], this receives a [KaiselStackContext] so
/// the builder can pattern-match on neighbours and decide whether
/// to render a standalone page or an absorbing one that consumes
/// entries below.
///
/// See [KaiselRouterDelegate.adaptive] for how to wire one up.
typedef KaiselAdaptivePageBuilder<R extends KaiselRoute> =
    KaiselPageResult Function(
      BuildContext context,
      R route,
      KaiselStackContext<R> stack,
    );

/// Convenience widget for master-detail layouts.
///
/// Renders [master] and [detail] side by side with an optional
/// divider between them. Use inside a [KaiselAbsorbingPage]'s widget
/// to lay out the absorbed master and the absorbing detail.
///
/// This is purely a convenience; replace with your own layout if
/// you need different breakpoints, ratios, or chrome.
class KaiselMasterDetailScaffold extends StatelessWidget {
  /// Lay [master] and [detail] side by side.
  const KaiselMasterDetailScaffold({
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

/// Internal page key used by the adaptive pipeline. Carries two
/// integer ids: [stableId] (used for [Navigator] page identity) and
/// [popId] (used by host code that turns a removed page back into a
/// router entry id).
///
/// For standalone pages the two are identical: the entry's own id.
/// For absorbing pages [stableId] is the lowest absorbed entry's id
/// (so toggling absorbed/standalone preserves Navigator identity
/// across detail swaps), and [popId] is the top absorbing entry's
/// id (so OS back pops the top of the logical stack, not the lowest
/// absorbed entry).
///
/// Equality and hashCode use only [stableId]; [popId] is opaque to
/// [Navigator]. This is what gives master-detail its in-place feel:
/// `[List, DetailA]` and `[List, DetailB]` produce equal keys, so
/// Navigator doesn't animate between them.
///
/// Internal to the package. Not exported from `kaisel.dart`. Users
/// don't need to construct or read this directly: their page builder
/// returns a [KaiselPageResult], and the host widgets do the key
/// bookkeeping.
@immutable
class KaiselAdaptiveKey extends LocalKey {
  /// Create an adaptive key with separate identity and pop targets.
  const KaiselAdaptiveKey(this.stableId, this.popId);

  /// Id used by [Navigator] to decide whether two pages are the same.
  /// For absorbing pages this is the lowest absorbed entry's id.
  final int stableId;

  /// Id of the router entry to remove when this page is popped.
  /// For absorbing pages this is the top absorbing entry's id (the
  /// "topmost logical entry"), not the lowest absorbed one.
  final int popId;

  @override
  bool operator ==(Object other) =>
      other is KaiselAdaptiveKey && other.stableId == stableId;

  @override
  int get hashCode => stableId.hashCode;

  @override
  String toString() => 'KaiselAdaptiveKey(stable: $stableId, pop: $popId)';
}

/// Build a list of pages from a stack of entries using an adaptive
/// page builder. Handles absorption by iterating top-down and
/// skipping the absorbed entries below a [KaiselAbsorbingPage].
///
/// [wrap] turns a [KaiselPageWrapperContext] into a concrete [Page].
/// Hosts pass a function that applies their own page wrapper
/// (typically a [MaterialPage], or whatever the host's user
/// supplied). The helper computes the wrapper context with each
/// page's rendered position, total rendered length, and the route
/// of the page below it (the rendered "previous", not the router
/// stack's neighbour).
///
/// Used internally by `KaiselRouterDelegate.adaptive` and by
/// `KaiselInnerNavigator` (which is itself used by `KaiselBranch`,
/// `KaiselShell`, and `KaiselModuleMount`). Exposed because it has no
/// dependencies on those host widgets and is sometimes useful to
/// call from a custom host.
List<Page<Object?>> buildAdaptivePages<R extends KaiselRoute>({
  required BuildContext context,
  required List<KaiselStackEntry<R>> entries,
  required KaiselAdaptivePageBuilder<R> builder,
  required Page<Object?> Function(KaiselPageWrapperContext<R> ctx) wrap,
}) {
  final stack = [for (final e in entries) e.route];

  // First pass: top-down iteration collects (route, key, child)
  // tuples for each rendered page. Each absorbing entry skips its
  // absorbed neighbours below.
  final tuples = <_RenderedPageTuple<R>>[];
  var i = stack.length - 1;
  while (i >= 0) {
    final ctx = KaiselStackContext<R>(stack: stack, position: i);
    final result = builder(context, stack[i], ctx);

    switch (result) {
      case KaiselStandalonePage(:final widget):
        tuples.insert(
          0,
          _RenderedPageTuple<R>(
            route: stack[i],
            key: KaiselAdaptiveKey(entries[i].id, entries[i].id),
            child: widget,
          ),
        );
        i--;
      case KaiselAbsorbingPage(:final widget, :final absorbing):
        var lowestIdx = i - absorbing;
        if (lowestIdx < 0) {
          // Pathological: route asked to absorb more entries than
          // exist below it. Clamp to absorbing what's available.
          assert(
            false,
            'KaiselAbsorbingPage(absorbing: $absorbing) at position $i '
            'overflows the stack of length ${stack.length}',
          );
          lowestIdx = 0;
        }
        tuples.insert(
          0,
          _RenderedPageTuple<R>(
            route: stack[i],
            key: KaiselAdaptiveKey(entries[lowestIdx].id, entries[i].id),
            child: widget,
          ),
        );
        i = lowestIdx - 1;
    }
  }

  // Second pass: wrap each tuple with full rendered-stack context.
  // `previous` is the route of the rendered page below this one
  // (not the router-stack neighbour). For absorbing pages this is
  // the route of the absorbing entry of the page below.
  //
  // The child is also wrapped in a KaiselPageScope before
  // being passed to the wrap callback, so descendants of the
  // page's content can read navigation context via
  // KaiselPageScope.of(context).
  return [
    for (var pos = 0; pos < tuples.length; pos++)
      wrap(
        KaiselPageWrapperContext<R>(
          route: tuples[pos].route,
          child: KaiselPageScope(
            route: tuples[pos].route,
            position: pos,
            stackLength: tuples.length,
            previous: pos > 0 ? tuples[pos - 1].route : null,
            child: tuples[pos].child,
          ),
          key: tuples[pos].key,
          position: pos,
          stackLength: tuples.length,
          previous: pos > 0 ? tuples[pos - 1].route : null,
        ),
      ),
  ];
}

/// Internal: a (route, key, child) tuple collected during the first
/// pass of [buildAdaptivePages]. Held briefly so the second pass
/// can attach rendered position and previous-route context.
class _RenderedPageTuple<R extends KaiselRoute> {
  _RenderedPageTuple({
    required this.route,
    required this.key,
    required this.child,
  });

  final R route;
  final LocalKey key;
  final Widget child;
}

/// Extract a router-entry id from a removed page's key. Returns
/// `null` if the page key isn't recognised (which means the page
/// wasn't built by kaisel's pipelines).
///
/// Hosts call this in their `Navigator.onDidRemovePage` to turn the
/// removed page back into the entry id to pop from the router.
///
/// Internal.
int? adaptiveEntryIdFromPageKey(LocalKey? key) {
  if (key is KaiselAdaptiveKey) return key.popId;
  if (key is ValueKey<int>) return key.value;
  return null;
}
