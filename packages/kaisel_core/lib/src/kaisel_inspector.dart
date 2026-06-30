/// Debug-only inspection surface for kaisel's navigation state.
///
/// This file is the contract between a running kaisel app and a DevTools
/// extension (or an in-app overlay): a renderer-agnostic [KaiselNavSnapshot]
/// that the [KaiselInspector] publishes over `dart:developer`. Nothing here
/// runs unless something registers a [KaiselInspectable] — the kaisel
/// `KaiselRouterDelegate` does so only in `kDebugMode`, so release builds pay
/// nothing.
///
/// Everything is stringified (`route.toString()`, `props.map((p) => '$p')`);
/// the snapshot never serialises the live route objects, which may hold
/// non-serialisable values (a `Cart`, a callback).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'kaisel_notifier.dart';

/// A full navigation snapshot: the schema version plus one entry per live
/// root (usually exactly one delegate).
class KaiselNavSnapshot {
  /// Create a snapshot of [roots] at schema [version].
  const KaiselNavSnapshot({this.version = 1, required this.roots});

  /// Schema version. Bumped only on breaking changes; additive changes keep
  /// the same version and consumers ignore unknown fields.
  final int version;

  /// One snapshot per live root (delegate).
  final List<KaiselRootSnapshot> roots;

  /// Serialise to the wire format consumed by the extension.
  Map<String, Object?> toJson() => <String, Object?>{
    'v': version,
    'roots': <Object?>[for (final root in roots) root.toJson()],
  };
}

/// One app call frame behind a navigation, for the "who navigated" view: a
/// [display] line plus the parsed [uri] / [line] / [column] when the frame
/// could be located, so a DevTools host can open it in an editor.
class KaiselOriginFrame {
  /// Create an origin frame.
  const KaiselOriginFrame({
    required this.display,
    this.uri,
    this.line,
    this.column,
  });

  /// The trimmed frame line, as shown.
  final String display;

  /// The source URI (`package:…` / `file://…`), or null if unparsed.
  final String? uri;

  /// 1-based line, or null if unparsed.
  final int? line;

  /// 1-based column, or null if unparsed.
  final int? column;

  /// Serialise to the wire format.
  Map<String, Object?> toJson() => <String, Object?>{
    'display': display,
    'uri': ?uri,
    'line': ?line,
    'column': ?column,
  };

  @override
  bool operator ==(Object other) =>
      other is KaiselOriginFrame &&
      other.display == display &&
      other.uri == uri &&
      other.line == line &&
      other.column == column;

  @override
  int get hashCode => Object.hash(display, uri, line, column);
}

/// One root's navigation state: its main stack plus any shells, modules,
/// active flows, the last guard run, and the encoded URL.
class KaiselRootSnapshot {
  /// Create a root snapshot.
  const KaiselRootSnapshot({
    required this.id,
    required this.main,
    this.branches = const <KaiselShellSnapshot>[],
    this.modules = const <KaiselModuleSnapshot>[],
    this.flows = const <KaiselFlowSnapshot>[],
    this.problems = const <KaiselProblemSnapshot>[],
    this.guardTrace,
    this.url,
    this.history = const <String>[],
    this.origin = const <KaiselOriginFrame>[],
    this.replacesHistory = false,
  });

  /// Stable id distinguishing this root from others (multi-delegate apps).
  final String id;

  /// The main router's stack.
  final KaiselStackSnapshot main;

  /// Branched shells registered with this root.
  final List<KaiselShellSnapshot> branches;

  /// Module mounts registered with this root.
  final List<KaiselModuleSnapshot> modules;

  /// Active modal flows, outermost first.
  final List<KaiselFlowSnapshot> flows;

  /// Detected problems (e.g. no-op mutations), across this root's routers.
  final List<KaiselProblemSnapshot> problems;

  /// The most recent guard-pipeline run, or null if none retained.
  final KaiselGuardTraceSnapshot? guardTrace;

  /// The URL the current configuration encodes to, or null when no codec.
  final String? url;

  /// The main router's past stacks (oldest first), each as a "A → B" label, for
  /// DevTools time-travel. Empty in release.
  final List<String> history;

  /// App-code call frames behind the most recent transition (closest first),
  /// for the Transitions log — "who navigated". Empty in release, or when the
  /// change had no app call site (e.g. a system-back pop).
  final List<KaiselOriginFrame> origin;

  /// Whether the most recent committed change overwrites the browser history
  /// entry (`replaceTop` / `set`) rather than adding one (`push` / `pop`). What
  /// the route-information provider reports to the platform.
  final bool replacesHistory;

  /// Serialise to the wire format.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'main': main.toJson(),
    'branches': <Object?>[for (final shell in branches) shell.toJson()],
    'modules': <Object?>[for (final module in modules) module.toJson()],
    'flows': <Object?>[for (final flow in flows) flow.toJson()],
    'problems': <Object?>[for (final problem in problems) problem.toJson()],
    'guardTrace': guardTrace?.toJson(),
    'url': url,
    'history': history,
    'origin': <Object?>[for (final frame in origin) frame.toJson()],
    'replacesHistory': replacesHistory,
  };
}

/// A detected problem in the navigation state, surfaced in the Problems panel.
class KaiselProblemSnapshot {
  /// Create a problem snapshot.
  const KaiselProblemSnapshot({
    required this.kind,
    required this.router,
    required this.detail,
  });

  /// The problem kind, e.g. `'noOp'`.
  final String kind;

  /// Which router it occurred on, e.g. `'main'`, `'shell0.branch1'`,
  /// `'flow:0'`.
  final String router;

  /// A human-readable description.
  final String detail;

  /// Serialise to the wire format.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'router': router,
    'detail': detail,
  };
}

/// A single router's stack: its depth, whether it can pop, and its entries.
class KaiselStackSnapshot {
  /// Create a stack snapshot.
  const KaiselStackSnapshot({
    required this.depth,
    required this.canPop,
    required this.entries,
  });

  /// Number of routes on the stack.
  final int depth;

  /// Whether a pop would remove a route.
  final bool canPop;

  /// The stack entries, bottom to top.
  final List<KaiselEntrySnapshot> entries;

  /// Serialise to the wire format.
  Map<String, Object?> toJson() => <String, Object?>{
    'depth': depth,
    'canPop': canPop,
    'entries': <Object?>[for (final entry in entries) entry.toJson()],
  };
}

/// One stack entry: its identity-stable id, route type, props, and label.
class KaiselEntrySnapshot {
  /// Create an entry snapshot.
  const KaiselEntrySnapshot({
    required this.id,
    required this.type,
    required this.props,
    required this.label,
    this.absorbed = false,
  });

  /// Identity-stable entry id (preserved across value-equal routes). Index-
  /// based for stacks without entry identity (branches/modules).
  final int id;

  /// The route's runtime type name.
  final String type;

  /// Each declared prop, stringified.
  final List<String> props;

  /// The route's `toString()`.
  final String label;

  /// Whether this entry is absorbed into the rendered page above it (adaptive
  /// master-detail) — it has no Navigator page of its own at the current
  /// breakpoint. False for non-adaptive stacks.
  final bool absorbed;

  /// Serialise to the wire format.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'type': type,
    'props': props,
    'label': label,
    'absorbed': absorbed,
  };
}

/// A branched shell: the active branch and every branch's own stack.
class KaiselShellSnapshot {
  /// Create a shell snapshot.
  const KaiselShellSnapshot({
    required this.type,
    required this.activeBranch,
    required this.branchCount,
    required this.branches,
  });

  /// The shell's runtime type name.
  final String type;

  /// Index of the active branch.
  final int activeBranch;

  /// Number of branches.
  final int branchCount;

  /// Each branch's snapshot.
  final List<KaiselBranchSnapshot> branches;

  /// Serialise to the wire format.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'branched',
    'type': type,
    'activeBranch': activeBranch,
    'branchCount': branchCount,
    'branches': <Object?>[for (final branch in branches) branch.toJson()],
  };
}

/// One branch of a shell: its index, whether it is built, route-type hint, and
/// stack.
class KaiselBranchSnapshot {
  /// Create a branch snapshot.
  const KaiselBranchSnapshot({
    required this.index,
    required this.built,
    required this.routeType,
    required this.stack,
  });

  /// The branch index.
  final int index;

  /// Whether the branch is materialised. A lazy shell builds a branch only on
  /// first activation; an unbuilt branch has an empty [stack].
  final bool built;

  /// Best-effort route-type hint for the branch.
  final String routeType;

  /// The branch's stack (empty when not [built]).
  final KaiselStackSnapshot stack;

  /// Serialise to the wire format.
  Map<String, Object?> toJson() => <String, Object?>{
    'index': index,
    'built': built,
    'routeType': routeType,
    'stack': stack.toJson(),
  };
}

/// A mounted module: its optional URL prefix, route-type hint, and stack.
class KaiselModuleSnapshot {
  /// Create a module snapshot.
  const KaiselModuleSnapshot({
    this.prefix,
    required this.routeType,
    required this.stack,
  });

  /// The module's URL mount prefix, if known.
  final String? prefix;

  /// Best-effort route-type hint for the module.
  final String routeType;

  /// The module's internal stack.
  final KaiselStackSnapshot stack;

  /// Serialise to the wire format.
  Map<String, Object?> toJson() => <String, Object?>{
    'prefix': prefix,
    'routeType': routeType,
    'stack': stack.toJson(),
  };
}

/// An active modal flow: its nesting depth, type, result-type hint, and the
/// flow's own sub-stack.
class KaiselFlowSnapshot {
  /// Create a flow snapshot.
  const KaiselFlowSnapshot({
    required this.depth,
    required this.type,
    this.resultType,
    required this.stack,
  });

  /// Nesting depth (0 = outermost flow).
  final int depth;

  /// The flow's defining route type name.
  final String type;

  /// The flow's result type, if recoverable (usually null — erased).
  final String? resultType;

  /// The flow's own sub-router stack.
  final KaiselStackSnapshot stack;

  /// Serialise to the wire format.
  Map<String, Object?> toJson() => <String, Object?>{
    'depth': depth,
    'type': type,
    'resultType': resultType,
    'stack': stack.toJson(),
  };
}

/// The last guard-pipeline run: the proposed stack in, each guard's effect,
/// and the final stack out. Populated only when guard tracing is retained.
class KaiselGuardTraceSnapshot {
  /// Create a guard-trace snapshot.
  const KaiselGuardTraceSnapshot({
    required this.input,
    required this.steps,
    required this.output,
  });

  /// The proposed stack going in, as route labels.
  final List<String> input;

  /// One step per guard, in pipeline order.
  final List<KaiselGuardStepSnapshot> steps;

  /// The final stack the pipeline produced, as route labels.
  final List<String> output;

  /// Serialise to the wire format.
  Map<String, Object?> toJson() => <String, Object?>{
    'input': input,
    'steps': <Object?>[for (final step in steps) step.toJson()],
    'output': output,
  };
}

/// One guard's effect within a pipeline run.
class KaiselGuardStepSnapshot {
  /// Create a guard-step snapshot.
  const KaiselGuardStepSnapshot({
    required this.guard,
    required this.input,
    required this.output,
    required this.changed,
  });

  /// Best-effort guard label (closures are anonymous; index-based).
  final String guard;

  /// The stack this guard received, as route labels.
  final List<String> input;

  /// The stack this guard produced, as route labels.
  final List<String> output;

  /// Whether this guard changed the stack.
  final bool changed;

  /// Serialise to the wire format.
  Map<String, Object?> toJson() => <String, Object?>{
    'guard': guard,
    'in': input,
    'out': output,
    'changed': changed,
  };
}

/// What a root (the delegate) exposes to the [KaiselInspector].
///
/// The delegate is the hub: it knows the main router, the registered nested
/// handles (shells/modules), and the active flows, so one [debugSnapshot]
/// covers a whole root. [debugRevision] fires whenever that snapshot would
/// change.
abstract interface class KaiselInspectable {
  /// A snapshot of this root's navigation state.
  KaiselRootSnapshot debugSnapshot();

  /// Notifies whenever [debugSnapshot] would change.
  KaiselListenable get debugRevision;

  /// Decode [url] through this root's codec into a human-readable preview of
  /// the resulting stack, **without navigating**. Returns null if there's no
  /// codec or the URL doesn't decode. Powers the extension's deep-link preview.
  List<String>? debugDecode(String url);

  /// Apply a write [command] from DevTools (drive the app). Returns
  /// `{'ok': bool, 'message': String}`. Debug only.
  Future<Map<String, Object?>> debugApplyCommand(Map<String, Object?> command);
}

/// Debug-only registry that aggregates live roots and publishes navigation
/// snapshots to DevTools over the VM service.
///
/// Dormant until something registers — the kaisel delegate registers itself
/// in `kDebugMode` only, so release builds never reach this. Publishing is
/// coalesced into one event per microtask.
class KaiselInspector {
  KaiselInspector._();

  /// The shared inspector instance.
  static final KaiselInspector instance = KaiselInspector._();

  final Map<int, KaiselInspectable> _roots = <int, KaiselInspectable>{};
  int _nextToken = 0;
  bool _extensionsRegistered = false;
  bool _publishScheduled = false;

  /// Register [root]. Returns a token to pass to [deregister]. Subscribes to
  /// the root's revisions and schedules an immediate publish.
  int register(KaiselInspectable root) {
    final token = _nextToken++;
    _roots[token] = root;
    root.debugRevision.addListener(_schedulePublish);
    _ensureExtensions();
    _schedulePublish();
    return token;
  }

  /// Deregister the root previously registered under [token].
  void deregister(int token) {
    final root = _roots.remove(token);
    root?.debugRevision.removeListener(_schedulePublish);
    _schedulePublish();
  }

  /// Build a snapshot of every registered root. Synchronous; used both for
  /// the pushed event and the on-demand service extension.
  KaiselNavSnapshot snapshot() => KaiselNavSnapshot(
    roots: <KaiselRootSnapshot>[
      for (final root in _roots.values) root.debugSnapshot(),
    ],
  );

  void _schedulePublish() {
    if (_publishScheduled) return;
    _publishScheduled = true;
    scheduleMicrotask(() {
      _publishScheduled = false;
      _post('kaisel:nav', snapshot().toJson());
    });
  }

  void _ensureExtensions() {
    if (_extensionsRegistered) return;
    _extensionsRegistered = true;
    try {
      developer.registerExtension('ext.kaisel.snapshot', snapshotResponse);
      developer.registerExtension('ext.kaisel.decode', decodeResponse);
      developer.registerExtension('ext.kaisel.command', commandResponse);
    } catch (_) {
      // Already registered (e.g. a hot restart re-running this) — fine.
    }
  }

  /// Service-extension handler for `ext.kaisel.snapshot`.
  Future<developer.ServiceExtensionResponse> snapshotResponse(
    String method,
    Map<String, String> parameters,
  ) => Future<developer.ServiceExtensionResponse>.value(
    developer.ServiceExtensionResponse.result(snapshotJson()),
  );

  /// Service-extension handler for `ext.kaisel.decode`: a read-only deep-link
  /// preview that decodes a URL without navigating.
  Future<developer.ServiceExtensionResponse> decodeResponse(
    String method,
    Map<String, String> parameters,
  ) => Future<developer.ServiceExtensionResponse>.value(
    developer.ServiceExtensionResponse.result(
      decodeJson(parameters['url'] ?? ''),
    ),
  );

  /// Service-extension handler for `ext.kaisel.command`: applies a write
  /// command that drives the app. See [commandJson].
  Future<developer.ServiceExtensionResponse> commandResponse(
    String method,
    Map<String, String> parameters,
  ) async => developer.ServiceExtensionResponse.result(
    await commandJson(parameters['command'] ?? '{}'),
  );

  /// The current snapshot as a JSON string — the body of the
  /// `ext.kaisel.snapshot` service extension.
  String snapshotJson() => jsonEncode(snapshot().toJson());

  /// A deep-link preview as a JSON string (`{ok, lines}`) — the body of the
  /// `ext.kaisel.decode` service extension. Decodes [url] through the first
  /// registered root's codec, without navigating.
  String decodeJson(String url) {
    final root = _roots.values.isEmpty ? null : _roots.values.first;
    final lines = root?.debugDecode(url);
    return jsonEncode(<String, Object?>{
      'ok': lines != null,
      'lines': lines ?? <String>[],
    });
  }

  /// Apply the JSON-encoded write [command] to the first registered root;
  /// returns the result as a JSON string (`{ok, message}`).
  Future<String> commandJson(String command) async {
    final root = _roots.values.isEmpty ? null : _roots.values.first;
    if (root == null) {
      return jsonEncode(<String, Object?>{'ok': false, 'message': 'No root.'});
    }
    final Map<String, Object?> parsed;
    try {
      parsed = (jsonDecode(command) as Map).cast<String, Object?>();
    } catch (_) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'message': 'Malformed command.',
      });
    }
    return jsonEncode(await root.debugApplyCommand(parsed));
  }

  void _post(String event, Map<Object?, Object?> data) {
    try {
      developer.postEvent(event, data);
    } catch (_) {
      // No service connection (or unavailable in this environment) — fine.
    }
  }
}
