/// Client-side decode of the `kaisel:nav` wire format.
///
/// This mirrors the schema produced by `KaiselInspector` in kaisel_core. The
/// extension owns its own decoder (rather than importing the kaisel types) so
/// it stays a pure consumer of the versioned JSON contract. The slice classes
/// carry value equality (via [_Eq]) so the UI can skip rebuilding an unchanged
/// panel.
library;

Map<String, Object?> _obj(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const <String, Object?>{};

List<Object?> _list(Object? value) => value is List ? value : const <Object?>[];

List<String> _strings(Object? value) => <String>[
  for (final item in _list(value)) '$item',
];

/// Deep, list-aware equality over two field lists.
bool eqFields(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i];
    final y = b[i];
    if (x is List && y is List) {
      if (!eqFields(x, y)) return false;
    } else if (x != y) {
      return false;
    }
  }
  return true;
}

/// Value equality derived from a class's [_eqFields] (handles nested lists).
mixin _Eq {
  List<Object?> get _eqFields;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _Eq &&
          other.runtimeType == runtimeType &&
          eqFields(_eqFields, other._eqFields));

  @override
  int get hashCode => Object.hashAll(<Object?>[
    for (final f in _eqFields) f is List ? Object.hashAll(f) : f,
  ]);
}

/// A full navigation snapshot: schema version + one root per live delegate.
class NavSnapshot {
  /// Create a snapshot.
  NavSnapshot({required this.version, required this.roots});

  /// Decode from the wire format.
  factory NavSnapshot.fromJson(Map<String, Object?> json) => NavSnapshot(
    version: (json['v'] as num?)?.toInt() ?? 1,
    roots: <RootSnapshot>[
      for (final root in _list(json['roots']))
        RootSnapshot.fromJson(_obj(root)),
    ],
  );

  /// Schema version.
  final int version;

  /// One entry per live root.
  final List<RootSnapshot> roots;
}

/// One root's navigation state.
class RootSnapshot {
  /// Create a root snapshot.
  RootSnapshot({
    required this.id,
    required this.main,
    required this.branches,
    required this.modules,
    required this.flows,
    required this.problems,
    required this.guardTrace,
    required this.url,
    required this.history,
    required this.origin,
    required this.replacesHistory,
  });

  /// Decode from the wire format.
  factory RootSnapshot.fromJson(Map<String, Object?> json) => RootSnapshot(
    id: '${json['id'] ?? 'root'}',
    main: StackSnapshot.fromJson(_obj(json['main'])),
    branches: <ShellSnapshot>[
      for (final shell in _list(json['branches']))
        ShellSnapshot.fromJson(_obj(shell)),
    ],
    modules: <ModuleSnapshot>[
      for (final module in _list(json['modules']))
        ModuleSnapshot.fromJson(_obj(module)),
    ],
    flows: <FlowSnapshot>[
      for (final flow in _list(json['flows']))
        FlowSnapshot.fromJson(_obj(flow)),
    ],
    problems: <ProblemSnapshot>[
      for (final problem in _list(json['problems']))
        ProblemSnapshot.fromJson(_obj(problem)),
    ],
    guardTrace: json['guardTrace'] == null
        ? null
        : GuardTrace.fromJson(_obj(json['guardTrace'])),
    url: json['url'] as String?,
    history: _strings(json['history']),
    origin: <OriginFrame>[
      for (final frame in _list(json['origin']))
        OriginFrame.fromJson(_obj(frame)),
    ],
    replacesHistory: json['replacesHistory'] as bool? ?? false,
  );

  /// Stable root id.
  final String id;

  /// The main router's stack.
  final StackSnapshot main;

  /// Branched shells.
  final List<ShellSnapshot> branches;

  /// Mounted modules.
  final List<ModuleSnapshot> modules;

  /// Active modal flows.
  final List<FlowSnapshot> flows;

  /// Detected problems (e.g. no-op mutations).
  final List<ProblemSnapshot> problems;

  /// The last guard-pipeline run, if any.
  final GuardTrace? guardTrace;

  /// The encoded URL, if a codec is wired.
  final String? url;

  /// The main router's past stacks (oldest first), each as a "A → B" label.
  final List<String> history;

  /// App call frames behind the most recent transition (closest first) — the
  /// "who navigated" for the Transitions log. Empty when there was no app call
  /// site (a system-back pop) or in release.
  final List<OriginFrame> origin;

  /// Whether the most recent committed change overwrote the browser history
  /// entry (`replaceTop` / `set`) rather than adding one (`push` / `pop`).
  final bool replacesHistory;
}

/// One app call frame behind a navigation: a display line plus, when parsed,
/// the source location the host can open in an editor.
class OriginFrame {
  /// Create an origin frame.
  OriginFrame({required this.display, this.uri, this.line, this.column});

  /// Decode from the wire format.
  factory OriginFrame.fromJson(Map<String, Object?> json) => OriginFrame(
    display: '${json['display'] ?? ''}',
    uri: json['uri'] as String?,
    line: (json['line'] as num?)?.toInt(),
    column: (json['column'] as num?)?.toInt(),
  );

  /// The trimmed frame line, as shown.
  final String display;

  /// The source URI (`package:…` / `file://…`), or null if unparsed.
  final String? uri;

  /// 1-based line, or null if unparsed.
  final int? line;

  /// 1-based column, or null if unparsed.
  final int? column;

  /// Whether this frame has enough location to open in an editor.
  bool get canOpen => uri != null && line != null;

  @override
  bool operator ==(Object other) =>
      other is OriginFrame &&
      other.display == display &&
      other.uri == uri &&
      other.line == line &&
      other.column == column;

  @override
  int get hashCode => Object.hash(display, uri, line, column);
}

/// A detected problem in the navigation state.
class ProblemSnapshot with _Eq {
  /// Create a problem.
  ProblemSnapshot({
    required this.kind,
    required this.router,
    required this.detail,
  });

  /// Decode from the wire format.
  factory ProblemSnapshot.fromJson(Map<String, Object?> json) =>
      ProblemSnapshot(
        kind: '${json['kind'] ?? 'problem'}',
        router: '${json['router'] ?? '?'}',
        detail: '${json['detail'] ?? ''}',
      );

  /// The problem kind, e.g. `'noOp'`.
  final String kind;

  /// Which router it occurred on.
  final String router;

  /// Human-readable description.
  final String detail;

  @override
  List<Object?> get _eqFields => <Object?>[kind, router, detail];
}

/// A single router's stack.
class StackSnapshot with _Eq {
  /// Create a stack snapshot.
  StackSnapshot({
    required this.depth,
    required this.canPop,
    required this.entries,
  });

  /// Decode from the wire format.
  factory StackSnapshot.fromJson(Map<String, Object?> json) => StackSnapshot(
    depth: (json['depth'] as num?)?.toInt() ?? 0,
    canPop: json['canPop'] == true,
    entries: <EntrySnapshot>[
      for (final entry in _list(json['entries']))
        EntrySnapshot.fromJson(_obj(entry)),
    ],
  );

  /// Stack depth.
  final int depth;

  /// Whether a pop would remove a route.
  final bool canPop;

  /// The entries, bottom to top.
  final List<EntrySnapshot> entries;

  @override
  List<Object?> get _eqFields => <Object?>[depth, canPop, entries];
}

/// One stack entry.
class EntrySnapshot with _Eq {
  /// Create an entry snapshot.
  EntrySnapshot({
    required this.id,
    required this.type,
    required this.props,
    required this.label,
    required this.absorbed,
  });

  /// Decode from the wire format.
  factory EntrySnapshot.fromJson(Map<String, Object?> json) => EntrySnapshot(
    id: (json['id'] as num?)?.toInt() ?? -1,
    type: '${json['type'] ?? '?'}',
    props: _strings(json['props']),
    label: '${json['label'] ?? json['type'] ?? '?'}',
    absorbed: json['absorbed'] == true,
  );

  /// Identity-stable entry id.
  final int id;

  /// Route type name.
  final String type;

  /// Stringified props.
  final List<String> props;

  /// The route label (`toString()`).
  final String label;

  /// Whether this entry is absorbed into the rendered page above it (adaptive
  /// master-detail) — no Navigator page of its own at the current breakpoint.
  final bool absorbed;

  @override
  List<Object?> get _eqFields => <Object?>[id, type, props, label, absorbed];
}

/// A branched shell.
class ShellSnapshot with _Eq {
  /// Create a shell snapshot.
  ShellSnapshot({
    required this.type,
    required this.activeBranch,
    required this.branchCount,
    required this.branches,
  });

  /// Decode from the wire format.
  factory ShellSnapshot.fromJson(Map<String, Object?> json) => ShellSnapshot(
    type: '${json['type'] ?? 'Shell'}',
    activeBranch: (json['activeBranch'] as num?)?.toInt() ?? 0,
    branchCount: (json['branchCount'] as num?)?.toInt() ?? 0,
    branches: <BranchSnapshot>[
      for (final branch in _list(json['branches']))
        BranchSnapshot.fromJson(_obj(branch)),
    ],
  );

  /// Shell type name.
  final String type;

  /// Active branch index.
  final int activeBranch;

  /// Branch count.
  final int branchCount;

  /// Per-branch snapshots.
  final List<BranchSnapshot> branches;

  @override
  List<Object?> get _eqFields => <Object?>[
    type,
    activeBranch,
    branchCount,
    branches,
  ];
}

/// One branch of a shell.
class BranchSnapshot with _Eq {
  /// Create a branch snapshot.
  BranchSnapshot({
    required this.index,
    required this.built,
    required this.routeType,
    required this.stack,
  });

  /// Decode from the wire format.
  factory BranchSnapshot.fromJson(Map<String, Object?> json) => BranchSnapshot(
    index: (json['index'] as num?)?.toInt() ?? 0,
    built: json['built'] as bool? ?? true,
    routeType: '${json['routeType'] ?? '?'}',
    stack: StackSnapshot.fromJson(_obj(json['stack'])),
  );

  /// Branch index.
  final int index;

  /// Whether the branch is materialised (a lazy shell builds on first visit).
  final bool built;

  /// Route-type hint.
  final String routeType;

  /// The branch's stack (empty when not [built]).
  final StackSnapshot stack;

  @override
  List<Object?> get _eqFields => <Object?>[index, built, routeType, stack];
}

/// A mounted module.
class ModuleSnapshot with _Eq {
  /// Create a module snapshot.
  ModuleSnapshot({
    required this.prefix,
    required this.routeType,
    required this.stack,
  });

  /// Decode from the wire format.
  factory ModuleSnapshot.fromJson(Map<String, Object?> json) => ModuleSnapshot(
    prefix: json['prefix'] as String?,
    routeType: '${json['routeType'] ?? '?'}',
    stack: StackSnapshot.fromJson(_obj(json['stack'])),
  );

  /// Mount prefix, if known.
  final String? prefix;

  /// Route-type hint.
  final String routeType;

  /// The module's stack.
  final StackSnapshot stack;

  @override
  List<Object?> get _eqFields => <Object?>[prefix, routeType, stack];
}

/// An active modal flow.
class FlowSnapshot with _Eq {
  /// Create a flow snapshot.
  FlowSnapshot({
    required this.depth,
    required this.type,
    required this.resultType,
    required this.stack,
  });

  /// Decode from the wire format.
  factory FlowSnapshot.fromJson(Map<String, Object?> json) => FlowSnapshot(
    depth: (json['depth'] as num?)?.toInt() ?? 0,
    type: '${json['type'] ?? 'Flow'}',
    resultType: json['resultType'] as String?,
    stack: StackSnapshot.fromJson(_obj(json['stack'])),
  );

  /// Nesting depth.
  final int depth;

  /// Flow type name.
  final String type;

  /// Result-type hint, if any.
  final String? resultType;

  /// The flow's sub-stack.
  final StackSnapshot stack;

  @override
  List<Object?> get _eqFields => <Object?>[depth, type, resultType, stack];
}

/// The last guard-pipeline run.
class GuardTrace with _Eq {
  /// Create a guard trace.
  GuardTrace({required this.input, required this.steps, required this.output});

  /// Decode from the wire format.
  factory GuardTrace.fromJson(Map<String, Object?> json) => GuardTrace(
    input: _strings(json['input']),
    steps: <GuardStep>[
      for (final step in _list(json['steps'])) GuardStep.fromJson(_obj(step)),
    ],
    output: _strings(json['output']),
  );

  /// Proposed stack in, as labels.
  final List<String> input;

  /// Per-guard steps.
  final List<GuardStep> steps;

  /// Final stack out, as labels.
  final List<String> output;

  @override
  List<Object?> get _eqFields => <Object?>[input, steps, output];
}

/// One guard's effect.
class GuardStep with _Eq {
  /// Create a guard step.
  GuardStep({
    required this.guard,
    required this.input,
    required this.output,
    required this.changed,
  });

  /// Decode from the wire format.
  factory GuardStep.fromJson(Map<String, Object?> json) => GuardStep(
    guard: '${json['guard'] ?? '?'}',
    input: _strings(json['in']),
    output: _strings(json['out']),
    changed: json['changed'] == true,
  );

  /// Guard label.
  final String guard;

  /// Stack received.
  final List<String> input;

  /// Stack produced.
  final List<String> output;

  /// Whether this guard changed the stack.
  final bool changed;

  @override
  List<Object?> get _eqFields => <Object?>[guard, input, output, changed];
}
