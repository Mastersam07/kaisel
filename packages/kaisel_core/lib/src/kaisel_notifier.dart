import 'package:meta/meta.dart';

/// Pure-Dart equivalent of Flutter's `Listenable`.
///
/// kaisel_core has no Flutter dependency, so it can't expose Flutter's
/// `Listenable`. The Flutter layer (`KaiselRouterDelegate`,
/// `KaiselInnerNavigator`, shells) registers `void Function()` callbacks;
/// Flutter's `VoidCallback` is exactly `void Function()`, so these
/// interoperate transparently with the framework.
abstract class KaiselListenable {
  /// Register [listener] to be called on every change notification.
  void addListener(void Function() listener);

  /// Remove a previously registered [listener]. Idempotent.
  void removeListener(void Function() listener);
}

/// Minimal pure-Dart re-implementation of `ChangeNotifier`.
///
/// Implements the subset of `ChangeNotifier`'s contract the router relies
/// on: snapshot-iterate on notify (so listeners may add/remove during
/// dispatch), idempotent removal, and throw-after-dispose. Unlike Flutter's
/// release-mode `ChangeNotifier`, [notifyListeners] throws if called after
/// [dispose] — matching the debug-mode contract the router documents and
/// already guards against.
class KaiselChangeNotifier implements KaiselListenable {
  List<void Function()>? _listeners = <void Function()>[];

  /// Whether [dispose] has been called.
  @protected
  bool get isDisposed => _listeners == null;

  @override
  void addListener(void Function() listener) {
    final listeners = _listeners;
    if (listeners == null) {
      throw StateError('addListener called on a disposed notifier.');
    }
    listeners.add(listener);
  }

  @override
  void removeListener(void Function() listener) {
    _listeners?.remove(listener);
  }

  /// Call every registered listener. Iterates over a snapshot so a listener
  /// may add or remove listeners during dispatch without disturbing the run.
  @protected
  void notifyListeners() {
    final listeners = _listeners;
    if (listeners == null) {
      throw StateError('notifyListeners called on a disposed notifier.');
    }
    for (final listener in List<void Function()>.of(listeners)) {
      listener();
    }
  }

  /// Release all listeners. Subsequent [addListener]/[notifyListeners] throw.
  @mustCallSuper
  void dispose() {
    _listeners = null;
  }
}
