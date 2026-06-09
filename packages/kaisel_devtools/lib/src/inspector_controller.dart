import 'dart:async';
import 'dart:convert';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/foundation.dart';
import 'package:kaisel_devtools/src/transitions.dart';

import 'snapshot.dart';

export 'transitions.dart' show Transition;

/// Connects to the running app's `KaiselInspector` and exposes the latest
/// navigation snapshot (plus the previous distinct one, for diffing).
///
/// Two channels, for robustness:
///  - **push**: ingests `kaisel:nav` events for instant updates on real
///    navigations;
///  - **poll**: a periodic `ext.kaisel.snapshot` pull that catches no-op
///    mutations (which update state without firing an event) and recovers
///    from any missed events or a reconnect.
class InspectorController extends ChangeNotifier {
  /// Create the controller and begin listening when connected.
  InspectorController() {
    serviceManager.connectedState.addListener(_onConnectionChanged);
    _onConnectionChanged();
  }

  static const Duration _pollInterval = Duration(milliseconds: 700);
  static const int _maxTransitions = 100;

  Timer? _timer;
  StreamSubscription<Object?>? _eventSub;
  String? _signature;

  /// The most recent decoded snapshot, or null before the first one.
  NavSnapshot? current;

  /// The previous *distinct* snapshot, for diffing against [current].
  NavSnapshot? previous;

  /// A chronological log of inferred navigations (most recent first), derived
  /// from consecutive snapshot deltas. Capped to the last [_maxTransitions], and
  /// reassigned (not mutated) on change so a memoised Log panel sees the update.
  List<Transition> transitions = const <Transition>[];

  /// Whether write commands are enabled — the "drive the app" toggle. Off by
  /// default: the user opts in, since commands mutate the running app.
  final ValueNotifier<bool> writeMode = ValueNotifier<bool>(false);

  /// The `{ok, message}` result of the last write command, for a status line.
  final ValueNotifier<String?> lastCommandResult = ValueNotifier<String?>(null);

  /// Whether a VM service connection is currently available.
  bool get connected => serviceManager.connectedState.value.connected;

  /// Send a write [command] to the app via `ext.kaisel.command`, recording the
  /// result in [lastCommandResult].
  Future<void> applyCommand(Map<String, Object?> command) async {
    try {
      final response = await serviceManager.callServiceExtensionOnMainIsolate(
        'ext.kaisel.command',
        args: <String, String>{'command': jsonEncode(command)},
      );
      final json = response.json;
      final ok = json?['ok'] == true;
      lastCommandResult.value =
          '${ok ? '✓' : '✗'} ${json?['message'] ?? (ok ? 'ok' : 'failed')}';
    } catch (e) {
      lastCommandResult.value = '✗ $e';
    }
  }

  void _onConnectionChanged() {
    if (connected) {
      _wire();
    } else {
      _unwire();
    }
    notifyListeners();
  }

  void _wire() {
    _timer ??= Timer.periodic(_pollInterval, (_) => unawaited(_poll()));
    final service = serviceManager.service;
    if (_eventSub == null && service != null) {
      try {
        unawaited(_listenExtensionStream());
        _eventSub = service.onExtensionEvent.listen((event) {
          if (event.extensionKind == 'kaisel:nav') {
            final data = event.extensionData?.data;
            if (data != null) _ingest(data);
          }
        });
      } catch (_) {
        // Event stream unavailable in this environment; polling still covers.
      }
    }
    unawaited(_poll());
  }

  void _unwire() {
    _timer?.cancel();
    _timer = null;
    unawaited(_eventSub?.cancel());
    _eventSub = null;
  }

  Future<void> _listenExtensionStream() async {
    try {
      await serviceManager.service?.streamListen('Extension');
    } catch (_) {
      // Already subscribed (DevTools owns the stream) — events still flow.
    }
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
      // The extension isn't registered yet (no kaisel delegate, or paused).
    }
  }

  void _ingest(Map<String, Object?> json) {
    final signature = jsonEncode(json);
    if (signature == _signature) return;
    _signature = signature;
    previous = current;
    current = NavSnapshot.fromJson(json);
    _recordTransitions(previous, current!);
    notifyListeners();
  }

  void _recordTransitions(NavSnapshot? prev, NavSnapshot next) {
    final added = diffTransitions(prev, next);
    if (added.isEmpty) return;
    final merged = <Transition>[...added.reversed, ...transitions];
    transitions = merged.length > _maxTransitions
        ? merged.sublist(0, _maxTransitions)
        : merged;
  }

  @override
  void dispose() {
    serviceManager.connectedState.removeListener(_onConnectionChanged);
    _unwire();
    writeMode.dispose();
    lastCommandResult.dispose();
    super.dispose();
  }
}
