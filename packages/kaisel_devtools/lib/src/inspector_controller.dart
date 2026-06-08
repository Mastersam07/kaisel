import 'dart:async';
import 'dart:convert';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/foundation.dart';

import 'snapshot.dart';

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

  /// Whether a VM service connection is currently available.
  bool get connected => serviceManager.connectedState.value.connected;

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
    if (prev == null || prev.roots.isEmpty || next.roots.isEmpty) return;
    final p = prev.roots.first;
    final n = next.roots.first;
    final added = <Transition>[];

    final mainOp = _stackOp(p.main.entries, n.main.entries);
    if (mainOp != null) {
      added.add(_transition(mainOp, 'main', p.main.entries, n.main.entries));
    }

    for (var s = 0; s < p.branches.length && s < n.branches.length; s++) {
      final ps = p.branches[s];
      final ns = n.branches[s];
      if (ps.activeBranch != ns.activeBranch) {
        added.add(
          Transition('switchBranch', 'shell$s', 'branch ${ns.activeBranch}'),
        );
      }
      for (var b = 0; b < ps.branches.length && b < ns.branches.length; b++) {
        final op = _stackOp(
          ps.branches[b].stack.entries,
          ns.branches[b].stack.entries,
        );
        if (op != null) {
          added.add(
            _transition(
              op,
              'shell$s.branch$b',
              ps.branches[b].stack.entries,
              ns.branches[b].stack.entries,
            ),
          );
        }
      }
    }

    final prevNoOps = <String>{
      for (final x in p.problems)
        if (x.kind == 'noOp') x.router,
    };
    for (final x in n.problems) {
      if (x.kind == 'noOp' && !prevNoOps.contains(x.router)) {
        added.add(Transition('no-op', x.router, '(value-equal — no change)'));
      }
    }

    if (added.isEmpty) return;
    final merged = <Transition>[...added.reversed, ...transitions];
    transitions = merged.length > _maxTransitions
        ? merged.sublist(0, _maxTransitions)
        : merged;
  }

  /// Infer the operation that turned [a] into [b], or null if unchanged.
  String? _stackOp(List<EntrySnapshot> a, List<EntrySnapshot> b) {
    if (a.length != b.length) return b.length > a.length ? 'push' : 'pop';
    if (a.isEmpty) return null;
    for (var i = 0; i < a.length; i++) {
      if (a[i].label != b[i].label) {
        return i == a.length - 1 ? 'replaceTop' : 'set';
      }
    }
    return null;
  }

  Transition _transition(
    String op,
    String router,
    List<EntrySnapshot> a,
    List<EntrySnapshot> b,
  ) {
    final label = op == 'pop'
        ? (a.isNotEmpty ? a.last.label : '?')
        : (b.isNotEmpty ? b.last.label : '?');
    return Transition(op, router, label);
  }

  @override
  void dispose() {
    serviceManager.connectedState.removeListener(_onConnectionChanged);
    _unwire();
    super.dispose();
  }
}

/// One inferred navigation in the transitions log.
class Transition {
  /// Create a transition.
  Transition(this.op, this.router, this.label);

  /// The inferred operation: push / pop / replaceTop / set / switchBranch /
  /// no-op.
  final String op;

  /// Which router it happened on (`main`, `shell0.branch1`, …).
  final String router;

  /// The route (or branch) involved.
  final String label;
}
