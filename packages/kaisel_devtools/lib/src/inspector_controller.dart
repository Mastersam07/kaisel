import 'dart:async';
import 'dart:convert';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/foundation.dart';

import 'snapshot.dart';

/// Polls the running app's `ext.kaisel.snapshot` service extension and exposes
/// the latest navigation snapshot (plus the previous distinct one, for diffing).
///
/// CP4 uses polling for robustness; the app also pushes `kaisel:nav` events,
/// which a later checkpoint can subscribe to for lower latency.
class InspectorController extends ChangeNotifier {
  /// Create the controller and begin polling when connected.
  InspectorController() {
    serviceManager.connectedState.addListener(_onConnectionChanged);
    _onConnectionChanged();
  }

  static const Duration _pollInterval = Duration(milliseconds: 700);

  Timer? _timer;
  String? _signature;

  /// The most recent decoded snapshot, or null before the first poll.
  NavSnapshot? current;

  /// The previous *distinct* snapshot, for diffing against [current].
  NavSnapshot? previous;

  /// Whether a VM service connection is currently available.
  bool get connected => serviceManager.connectedState.value.connected;

  void _onConnectionChanged() {
    if (connected) {
      _timer ??= Timer.periodic(_pollInterval, (_) => unawaited(_poll()));
      unawaited(_poll());
    } else {
      _timer?.cancel();
      _timer = null;
    }
    notifyListeners();
  }

  Future<void> _poll() async {
    if (!connected) return;
    try {
      final response = await serviceManager.callServiceExtensionOnMainIsolate(
        'ext.kaisel.snapshot',
      );
      final data = response.json;
      if (data != null) _ingest(data);
    } catch (_) {
      // The extension isn't registered (the app has no kaisel delegate yet,
      // or is paused). Keep polling; it may appear after a hot reload.
    }
  }

  void _ingest(Map<String, Object?> json) {
    final signature = jsonEncode(json);
    if (signature == _signature) return;
    _signature = signature;
    previous = current;
    current = NavSnapshot.fromJson(json);
    notifyListeners();
  }

  @override
  void dispose() {
    serviceManager.connectedState.removeListener(_onConnectionChanged);
    _timer?.cancel();
    super.dispose();
  }
}
