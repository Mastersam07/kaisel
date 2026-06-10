import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:kaisel_core/kaisel_core.dart';

/// Rebuilds a route from its restored [routeName] and [props] — the values from
/// [KaiselRoute.routeName] and [KaiselRoute.props], round-tripped through JSON.
///
/// Supplied by apps that want state restoration **without** a URL codec. It is
/// deserialize-only (kaisel serialises automatically), and `props` must be
/// JSON-encodable values for the round-trip to work.
///
/// ```dart
/// restoreRoute: (name, props) => switch (name) {
///   'Home' => const Home(),
///   'ProductDetail' => ProductDetail(props[0] as String),
///   _ => const Home(),
/// };
/// ```
typedef KaiselRouteRestorer<R extends KaiselRoute> =
    R Function(String routeName, List<Object?> props);

/// Persists the main stack to a restoration bucket and replays it on relaunch,
/// for apps with no URL codec. Installed by [KaiselRouterDelegate] when a
/// `restoreRoute` is supplied; restores the **main** stack only (nested shell /
/// module state still needs a codec).
class KaiselStackRestorer<R extends KaiselRoute> extends StatefulWidget {
  /// Bridge [router]'s stack to a restoration bucket, rebuilding routes with
  /// [restore].
  const KaiselStackRestorer({
    super.key,
    required this.router,
    required this.restore,
    required this.child,
  });

  /// The router whose stack is saved and restored.
  final KaiselRouter<R> router;

  /// Rebuilds a route from its restored name + props.
  final KaiselRouteRestorer<R> restore;

  /// The subtree below the restorer.
  final Widget child;

  @override
  State<KaiselStackRestorer<R>> createState() => _KaiselStackRestorerState<R>();
}

class _KaiselStackRestorerState<R extends KaiselRoute>
    extends State<KaiselStackRestorer<R>>
    with RestorationMixin {
  final RestorableStringN _saved = RestorableStringN(null);

  @override
  String? get restorationId => 'kaisel-stack';

  @override
  void initState() {
    super.initState();
    widget.router.addListener(_onChange);
  }

  @override
  void didUpdateWidget(KaiselStackRestorer<R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.router, widget.router)) {
      oldWidget.router.removeListener(_onChange);
      widget.router.addListener(_onChange);
    }
  }

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_saved, 'stack');
    final routes = _decode(_saved.value);
    if (routes.isNotEmpty) widget.router.restoreStack(routes);
  }

  void _onChange() {
    final encoded = _encode(widget.router.stack);
    if (encoded != null) _saved.value = encoded;
  }

  String? _encode(List<R> stack) {
    try {
      return jsonEncode(<Map<String, Object?>>[
        for (final route in stack)
          <String, Object?>{'name': route.routeName, 'props': route.props},
      ]);
    } catch (error) {
      assert(() {
        debugPrint(
          'kaisel: stack not restorable (props not JSON-able): $error',
        );
        return true;
      }());
      return null;
    }
  }

  List<R> _decode(String? data) {
    if (data == null || data.isEmpty) return const [];
    final list = (jsonDecode(data) as List).cast<Map<String, Object?>>();
    return <R>[
      for (final entry in list)
        _rebuild(
          entry['name'] as String,
          (entry['props'] as List?)?.cast<Object?>() ?? const <Object?>[],
        ),
    ];
  }

  R _rebuild(String name, List<Object?> props) {
    final route = widget.restore(name, props);
    assert(() {
      if (route.routeName != name) {
        debugPrint(
          'kaisel: restoreRoute gave "${route.routeName}" for saved name "$name" '
          '— the route is unhandled, or routeName is minified under --obfuscate. '
          'Override routeName with a stable literal so both sides agree.',
        );
      }
      return true;
    }());
    return route;
  }

  @override
  void dispose() {
    widget.router.removeListener(_onChange);
    _saved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
