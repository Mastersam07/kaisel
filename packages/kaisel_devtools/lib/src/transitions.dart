import 'snapshot.dart';

/// One inferred navigation in the transitions log.
class Transition {
  /// Create a transition.
  Transition(
    this.op,
    this.router,
    this.label, {
    this.origin = const <OriginFrame>[],
  });

  /// The inferred operation: push / pop / replaceTop / set / switchBranch /
  /// no-op.
  final String op;

  /// Which router it happened on (`main`, `shell0.branch1`, …).
  final String router;

  /// The route (or branch) involved.
  final String label;

  /// App call frames behind this navigation (closest first), or empty when the
  /// running app reported none (a system-back pop, or a release build).
  final List<OriginFrame> origin;
}

/// Infer the navigations between two consecutive snapshots (main stack, then
/// each shell branch, then newly-appeared no-ops), in computation order. Pure;
/// the controller prepends the reverse of this to its capped log.
List<Transition> diffTransitions(NavSnapshot? prev, NavSnapshot next) {
  final added = <Transition>[];
  if (prev == null || prev.roots.isEmpty || next.roots.isEmpty) return added;
  final p = prev.roots.first;
  final n = next.roots.first;

  // The snapshot's origin belongs to the change this delta surfaces.
  final origin = n.origin;

  final mainOp = stackOp(p.main.entries, n.main.entries);
  if (mainOp != null) {
    added.add(
      _transition(mainOp, 'main', p.main.entries, n.main.entries, origin),
    );
  }

  for (var s = 0; s < p.branches.length && s < n.branches.length; s++) {
    final ps = p.branches[s];
    final ns = n.branches[s];
    if (ps.activeBranch != ns.activeBranch) {
      added.add(
        Transition(
          'switchBranch',
          'shell$s',
          'branch ${ns.activeBranch}',
          origin: origin,
        ),
      );
    }
    for (var b = 0; b < ps.branches.length && b < ns.branches.length; b++) {
      final op = stackOp(
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
            origin,
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

  return added;
}

/// Infer the operation that turned stack [a] into stack [b], or null if
/// unchanged: grow → push, shrink → pop, top differs → replaceTop, an inner
/// entry differs → set.
String? stackOp(List<EntrySnapshot> a, List<EntrySnapshot> b) {
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
  List<OriginFrame> origin,
) {
  final label = op == 'pop'
      ? (a.isNotEmpty ? a.last.label : '?')
      : (b.isNotEmpty ? b.last.label : '?');
  return Transition(op, router, label, origin: origin);
}
