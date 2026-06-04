import 'package:flutter/widgets.dart';
import 'package:kaisel_core/framework.dart';

/// A Flutter [Listenable] view over a kaisel listenable (a [KaiselRouter]).
///
/// A stateless pass-through: it owns no listeners of its own, forwarding
/// registration straight to the source, so it needs no disposal. Two adapters
/// over the same source compare equal, which makes it safe to construct inline
/// in a build method without churning [ListenableBuilder]'s subscription.
class _KaiselListenableAdapter extends Listenable {
  _KaiselListenableAdapter(this._source);

  final KaiselListenable _source;

  @override
  void addListener(VoidCallback listener) => _source.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _source.removeListener(listener);

  @override
  bool operator ==(Object other) =>
      other is _KaiselListenableAdapter && identical(other._source, _source);

  @override
  int get hashCode => identityHashCode(_source);
}

/// Flutter interop for [KaiselRouter].
extension KaiselRouterListenable<R extends KaiselRoute> on KaiselRouter<R> {
  /// A Flutter [Listenable] adapter for this router, so it can drive
  /// [ListenableBuilder], [AnimatedBuilder], and anything else expecting a
  /// [Listenable].
  ///
  /// kaisel_core is Flutter-free, so a [KaiselRouter] is not itself a Flutter
  /// [Listenable]. The returned adapter is a stateless pass-through — it owns
  /// no listeners and needs no disposal, and inline construction is fine:
  ///
  /// ```dart
  /// ListenableBuilder(
  ///   listenable: router.asListenable(),
  ///   builder: (context, _) => Text('depth: ${router.depth}'),
  /// );
  /// ```
  ///
  /// For the common rebuild-on-change case, prefer [KaiselListenableBuilder].
  Listenable asListenable() => _KaiselListenableAdapter(this);
}

/// Rebuilds [builder] whenever [router] notifies — the kaisel equivalent of
/// [ListenableBuilder] for a [KaiselRouter].
///
/// Because kaisel_core is Flutter-free, a [KaiselRouter] isn't a Flutter
/// [Listenable] and can't be handed to [ListenableBuilder] directly. This
/// widget bridges the gap: it subscribes to the router, rebuilds on every
/// change, and unsubscribes on dispose.
///
/// ```dart
/// KaiselListenableBuilder<AppRoute>(
///   router: router,
///   builder: (context, _) => Text('depth: ${router.depth}'),
/// );
/// ```
///
/// For raw [ListenableBuilder] / [AnimatedBuilder] use, see
/// [KaiselRouterListenable.asListenable].
class KaiselListenableBuilder<R extends KaiselRoute> extends StatefulWidget {
  /// Create a builder that rebuilds when [router] changes.
  const KaiselListenableBuilder({
    super.key,
    required this.router,
    required this.builder,
    this.child,
  });

  /// The router whose notifications trigger a rebuild.
  final KaiselRouter<R> router;

  /// Called on build and on every router notification. The second argument is
  /// [child], passed through unchanged.
  final TransitionBuilder builder;

  /// Optional subtree that doesn't depend on the router, hoisted out of the
  /// rebuild and handed back to [builder] as its second argument.
  final Widget? child;

  @override
  State<KaiselListenableBuilder<R>> createState() =>
      _KaiselListenableBuilderState<R>();
}

class _KaiselListenableBuilderState<R extends KaiselRoute>
    extends State<KaiselListenableBuilder<R>> {
  @override
  void initState() {
    super.initState();
    widget.router.addListener(_onChange);
  }

  @override
  void didUpdateWidget(covariant KaiselListenableBuilder<R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.router, widget.router)) {
      oldWidget.router.removeListener(_onChange);
      widget.router.addListener(_onChange);
    }
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.router.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.child);
}
