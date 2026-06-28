import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import 'inspector_controller.dart';
import 'memo.dart';
import 'snapshot.dart';

/// The snapshot schema version this extension understands. A snapshot with a
/// higher version means the app is newer than the extension.
const int _supportedSchemaVersion = 1;

/// Root of the inspector UI. Owns the [InspectorController] and rebuilds as
/// snapshots arrive.
class KaiselInspectorView extends StatefulWidget {
  /// Create the inspector view.
  const KaiselInspectorView({super.key});

  @override
  State<KaiselInspectorView> createState() => _KaiselInspectorViewState();
}

class _KaiselInspectorViewState extends State<KaiselInspectorView> {
  late final InspectorController _controller = InspectorController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (!_controller.connected) {
          return const _Message('Waiting for a VM service connection…');
        }
        final snapshot = _controller.current;
        if (snapshot == null) {
          return const _Message(
            'No kaisel router detected yet.\n'
            'Navigate in your app — or hot reload if it just started.',
          );
        }
        if (snapshot.roots.isEmpty) {
          return const _Message(
            'Connected, but no kaisel delegate is registered.',
          );
        }
        final previousRoots = _controller.previous?.roots;
        final view = _RootView(
          controller: _controller,
          root: snapshot.roots.first,
          previous: (previousRoots != null && previousRoots.isNotEmpty)
              ? previousRoots.first
              : null,
          transitions: _controller.transitions,
        );
        if (snapshot.version > _supportedSchemaVersion) {
          return Column(
            children: [
              _VersionBanner(appVersion: snapshot.version),
              Expanded(child: view),
            ],
          );
        }
        return view;
      },
    );
  }
}

class _VersionBanner extends StatelessWidget {
  const _VersionBanner({required this.appVersion});

  final int appVersion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.tertiaryContainer,
      padding: const EdgeInsets.all(8),
      child: Text(
        'The kaisel app speaks snapshot schema v$appVersion, but this DevTools '
        'extension understands v$_supportedSchemaVersion. Update the extension; '
        'showing what is recognised.',
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}

class _RootView extends StatefulWidget {
  const _RootView({
    required this.controller,
    required this.root,
    required this.previous,
    required this.transitions,
  });

  final InspectorController controller;
  final RootSnapshot root;
  final RootSnapshot? previous;
  final List<Transition> transitions;

  @override
  State<_RootView> createState() => _RootViewState();
}

class _RootViewState extends State<_RootView> with TickerProviderStateMixin {
  TabController? _tabs;
  List<String> _keys = const <String>[];

  // The stable identity of a tab, ignoring any " (N)" count suffix.
  static String _key(String label) {
    final i = label.indexOf(' (');
    return i < 0 ? label : label.substring(0, i);
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final root = widget.root;
    final previousMain = widget.previous?.main;

    final tabs = <(String, Widget)>[
      (
        'Stack',
        Memo(
          value: (root.main, previousMain),
          child: _StackList(
            controller: widget.controller,
            stack: root.main,
            previous: previousMain,
          ),
        ),
      ),
      if (root.branches.isNotEmpty)
        (
          'Shells',
          Memo(
            value: root.branches,
            child: _BranchesPanel(
              controller: widget.controller,
              shells: root.branches,
            ),
          ),
        ),
      if (root.flows.isNotEmpty)
        (
          'Flows',
          Memo(
            value: root.flows,
            child: _FlowsPanel(
              controller: widget.controller,
              flows: root.flows,
            ),
          ),
        ),
      if (root.modules.isNotEmpty)
        (
          'Modules',
          Memo(
            value: root.modules,
            child: _ModulesPanel(modules: root.modules),
          ),
        ),
      if (root.problems.isNotEmpty)
        (
          'Problems (${root.problems.length})',
          Memo(
            value: root.problems,
            child: _ProblemsPanel(problems: root.problems),
          ),
        ),
      (
        'Guards',
        Memo(
          value: root.guardTrace,
          child: _GuardPanel(trace: root.guardTrace),
        ),
      ),
      (
        'URL',
        Memo(
          value: (root.url, root.replacesHistory),
          child: _UrlPanel(
            controller: widget.controller,
            url: root.url,
            replacesHistory: root.replacesHistory,
          ),
        ),
      ),
      if (widget.transitions.isNotEmpty)
        (
          'Log (${widget.transitions.length})',
          Memo(
            value: widget.transitions,
            child: _TransitionsPanel(
              controller: widget.controller,
              transitions: widget.transitions,
            ),
          ),
        ),
      if (root.history.isNotEmpty)
        (
          'History (${root.history.length})',
          Memo(
            value: root.history,
            child: _HistoryPanel(
              controller: widget.controller,
              history: root.history,
            ),
          ),
        ),
    ];

    // Recreate the controller only when the *set* of tabs (by stable key)
    // changes, and preserve the selected tab across the change — otherwise it
    // resets to the first tab every time a panel appears or disappears.
    final keys = [for (final (label, _) in tabs) _key(label)];
    if (_tabs == null || !listEquals(keys, _keys)) {
      final selected = (_tabs != null && _keys.isNotEmpty)
          ? _keys[_tabs!.index.clamp(0, _keys.length - 1)]
          : null;
      final restored = selected == null ? 0 : keys.indexOf(selected);
      _tabs?.dispose();
      _tabs = TabController(
        length: tabs.length,
        vsync: this,
        initialIndex: restored < 0 ? 0 : restored,
      );
      _keys = keys;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(controller: widget.controller, root: root),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final (label, _) in tabs) Tab(text: label)],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            // Keyed by tab name so a panel stays matched to its state when the
            // tab set changes.
            children: [
              for (final (label, panel) in tabs)
                KeyedSubtree(key: ValueKey(_key(label)), child: panel),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.root});

  final InspectorController controller;
  final RootSnapshot root;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <String>[
      'depth ${root.main.depth}',
      if (root.branches.isNotEmpty) '${root.branches.length} shell(s)',
      if (root.modules.isNotEmpty) '${root.modules.length} module(s)',
      if (root.flows.isNotEmpty) '${root.flows.length} flow(s)',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
      child: Row(
        children: [
          Icon(
            Icons.account_tree_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(root.id, style: theme.textTheme.titleSmall),
          const SizedBox(width: 12),
          Text(parts.join('  ·  '), style: theme.textTheme.bodySmall),
          const Spacer(),
          ValueListenableBuilder<String?>(
            valueListenable: controller.lastCommandResult,
            builder: (context, result, _) => result == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      result,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: result.startsWith('✓')
                            ? theme.colorScheme.primary
                            : theme.colorScheme.error,
                      ),
                    ),
                  ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: controller.writeMode,
            builder: (context, write, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message:
                      'Enable commands that drive (mutate) the running app',
                  child: Text('Write', style: theme.textTheme.bodySmall),
                ),
                Switch(
                  value: write,
                  onChanged: (v) => controller.writeMode.value = v,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A button that sends [command] via the controller — enabled only in write
/// mode (the global "drive the app" toggle).
class _WriteButton extends StatelessWidget {
  const _WriteButton({
    required this.controller,
    required this.icon,
    required this.label,
    required this.command,
  });

  final InspectorController controller;
  final IconData icon;
  final String label;
  final Map<String, Object?> command;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: controller.writeMode,
      builder: (context, write, _) => OutlinedButton.icon(
        onPressed: write ? () => controller.applyCommand(command) : null,
        icon: Icon(icon, size: 14),
        label: Text(label),
        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
      ),
    );
  }
}

class _StackList extends StatelessWidget {
  const _StackList({
    required this.controller,
    required this.stack,
    this.previous,
  });

  final InspectorController controller;
  final StackSnapshot stack;

  /// The previous main stack, for the diff highlight. Entries whose id is absent
  /// from it are flagged as newly pushed; null disables highlighting.
  final StackSnapshot? previous;

  @override
  Widget build(BuildContext context) {
    final previousIds = previous == null
        ? null
        : <int>{for (final e in previous!.entries) e.id};
    final ordered = stack.entries.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Row(
            children: [
              _WriteButton(
                controller: controller,
                icon: Icons.undo,
                label: 'Pop top',
                command: const <String, Object?>{'cmd': 'pop'},
              ),
            ],
          ),
        ),
        Expanded(
          child: ordered.isEmpty
              ? const _Message('Empty.')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: ordered.length,
                  itemBuilder: (context, i) {
                    final entry = ordered[i];
                    final isTop = i == 0;
                    final isNew =
                        previousIds != null && !previousIds.contains(entry.id);
                    return _EntryTile(entry: entry, isTop: isTop, isNew: isNew);
                  },
                ),
        ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.isTop,
    required this.isNew,
  });

  final EntrySnapshot entry;
  final bool isTop;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
    final highlight = isNew ? theme.colorScheme.tertiary : Colors.transparent;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: highlight, width: 3)),
        color: isTop ? theme.colorScheme.primary.withValues(alpha: 0.06) : null,
      ),
      child: ListTile(
        dense: true,
        leading: _Badge(text: '#${entry.id}'),
        title: Text(entry.label, style: mono),
        subtitle: entry.props.isEmpty
            ? null
            : Text(
                'props: ${entry.props.join(', ')}',
                style: theme.textTheme.bodySmall,
              ),
        trailing: Wrap(
          spacing: 6,
          children: [
            if (entry.absorbed)
              const _Tag(text: 'absorbed', tone: _Tone.neutral),
            if (isTop) const _Tag(text: 'top', tone: _Tone.neutral),
            if (isNew) const _Tag(text: 'new', tone: _Tone.added),
          ],
        ),
      ),
    );
  }
}

class _BranchesPanel extends StatelessWidget {
  const _BranchesPanel({required this.controller, required this.shells});

  final InspectorController controller;
  final List<ShellSnapshot> shells;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (var s = 0; s < shells.length; s++) ...[
          Text(
            '${shells[s].type}  ·  branch '
            '${shells[s].activeBranch} / ${shells[s].branchCount}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          for (final branch in shells[s].branches)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Branch ${branch.index}  (${branch.routeType})',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(width: 8),
                        if (branch.index == shells[s].activeBranch)
                          const _Tag(text: 'active', tone: _Tone.added)
                        else ...[
                          if (!branch.built) ...[
                            const _Tag(text: 'not built', tone: _Tone.neutral),
                            const SizedBox(width: 8),
                          ],
                          _WriteButton(
                            controller: controller,
                            icon: Icons.swap_horiz,
                            label: 'Switch',
                            command: <String, Object?>{
                              'cmd': 'switchBranch',
                              'shell': s,
                              'branch': branch.index,
                            },
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (branch.built)
                      _MiniStack(stack: branch.stack)
                    else
                      Text(
                        'Lazy — builds on first visit.',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _FlowsPanel extends StatelessWidget {
  const _FlowsPanel({required this.controller, required this.flows});

  final InspectorController controller;
  final List<FlowSnapshot> flows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            _WriteButton(
              controller: controller,
              icon: Icons.close,
              label: 'Dismiss top flow',
              command: const <String, Object?>{'cmd': 'dismissFlow'},
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final flow in flows)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _Badge(text: 'depth ${flow.depth}'),
                      const SizedBox(width: 8),
                      Text(flow.type, style: theme.textTheme.labelLarge),
                      if (flow.resultType != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '→ ${flow.resultType}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  _MiniStack(stack: flow.stack),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ModulesPanel extends StatelessWidget {
  const _ModulesPanel({required this.modules});

  final List<ModuleSnapshot> modules;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final module in modules)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        module.prefix ?? module.routeType,
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${module.routeType})',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _MiniStack(stack: module.stack),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Compact, non-scrolling stack renderer used inside branch / flow / module
/// cards (top-of-stack first). No diff highlighting: these stacks carry
/// positional ids, so "new" wouldn't be meaningful.
class _MiniStack extends StatelessWidget {
  const _MiniStack({required this.stack});

  final StackSnapshot stack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    final ordered = stack.entries.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < ordered.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text(
              '${i == 0 ? '▸ ' : '  '}${ordered[i].label}'
              '${ordered[i].absorbed ? '  · absorbed' : ''}',
              style: ordered[i].absorbed
                  ? mono?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.hintColor,
                    )
                  : (i == 0
                        ? mono?.copyWith(fontWeight: FontWeight.bold)
                        : mono),
            ),
          ),
      ],
    );
  }
}

class _ProblemsPanel extends StatelessWidget {
  const _ProblemsPanel({required this.problems});

  final List<ProblemSnapshot> problems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final problem in problems)
          Card(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
            child: ListTile(
              leading: Icon(
                Icons.warning_amber_rounded,
                color: theme.colorScheme.error,
              ),
              title: Text(problem.detail),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    _Badge(text: problem.kind),
                    const SizedBox(width: 6),
                    _Badge(text: problem.router),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _GuardPanel extends StatelessWidget {
  const _GuardPanel({required this.trace});

  final GuardTrace? trace;

  @override
  Widget build(BuildContext context) {
    final t = trace;
    if (t == null) {
      return const _Message(
        'No guard run recorded.\n'
        'Guards run on navigation; trigger one to see the pipeline.',
      );
    }
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Input', style: theme.textTheme.labelLarge),
        Text(t.input.join('  →  '), style: mono),
        const Divider(height: 20),
        for (final step in t.steps)
          Card(
            child: ListTile(
              dense: true,
              leading: _Badge(text: step.guard),
              title: Text(step.input.join('  →  '), style: mono),
              subtitle: Text('out: ${step.output.join('  →  ')}', style: mono),
              trailing: _Tag(
                text: step.changed ? 'changed' : 'no-op',
                tone: step.changed ? _Tone.added : _Tone.neutral,
              ),
            ),
          ),
        const Divider(height: 20),
        Text('Output', style: theme.textTheme.labelLarge),
        Text(t.output.join('  →  '), style: mono),
      ],
    );
  }
}

class _UrlPanel extends StatefulWidget {
  const _UrlPanel({
    required this.controller,
    required this.url,
    required this.replacesHistory,
  });

  final InspectorController controller;
  final String? url;
  final bool replacesHistory;

  @override
  State<_UrlPanel> createState() => _UrlPanelState();
}

class _UrlPanelState extends State<_UrlPanel> {
  final TextEditingController _input = TextEditingController();
  List<String>? _decoded;
  bool _failed = false;
  bool _busy = false;

  Future<void> _decode() async {
    final url = _input.text.trim();
    if (url.isEmpty) return;
    setState(() => _busy = true);
    try {
      final response = await serviceManager.callServiceExtensionOnMainIsolate(
        'ext.kaisel.decode',
        args: <String, String>{'url': url},
      );
      final json = response.json;
      final ok = json?['ok'] == true;
      final lines = <String>[
        for (final line in (json?['lines'] as List?) ?? const <Object?>[])
          '$line',
      ];
      setState(() {
        _decoded = ok ? lines : null;
        _failed = !ok;
        _busy = false;
      });
    } catch (_) {
      setState(() {
        _decoded = null;
        _failed = true;
        _busy = false;
      });
    }
  }

  Future<void> _apply() async {
    final url = _input.text.trim();
    if (url.isEmpty) return;
    await widget.controller.applyCommand(<String, Object?>{
      'cmd': 'deepLink',
      'url': url,
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
    final url = widget.url;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Current URL', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        if (url == null)
          Text(
            'No codec wired — this app is URL-less.',
            style: theme.textTheme.bodyMedium,
          )
        else
          SelectableText(
            url,
            style: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'monospace'),
          ),
        if (url != null) ...[
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Last nav reported to history: '),
                TextSpan(
                  text: widget.replacesHistory ? 'replace' : 'push',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const Divider(height: 28),
        Text(
          'Decode a URL (preview), or Apply it (navigates — write mode)',
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                decoration: const InputDecoration(
                  hintText: '/app/inbox/m2',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _decode(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : _decode,
              child: const Text('Decode'),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<bool>(
              valueListenable: widget.controller.writeMode,
              builder: (context, write, _) => OutlinedButton(
                onPressed: write ? _apply : null,
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_failed)
          Text(
            'That URL did not decode (no codec, or the codec rejected it).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          )
        else if (_decoded case final lines?)
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(line, style: mono),
            ),
      ],
    );
  }
}

class _TransitionsPanel extends StatelessWidget {
  const _TransitionsPanel({
    required this.controller,
    required this.transitions,
  });

  final InspectorController controller;
  final List<Transition> transitions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
    final origin = mono?.copyWith(fontSize: 11, color: theme.hintColor);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: transitions.length,
      itemBuilder: (context, i) {
        final t = transitions[i];
        final noOp = t.op == 'no-op';
        final tag = _Tag(text: t.op, tone: noOp ? _Tone.added : _Tone.neutral);
        final badge = _Badge(text: t.router);
        if (t.origin.isEmpty) {
          return ListTile(
            dense: true,
            leading: tag,
            title: Text(t.label, style: mono),
            trailing: badge,
          );
        }
        return ExpansionTile(
          dense: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: tag,
          title: Row(
            children: [
              Expanded(child: Text(t.label, style: mono)),
              const SizedBox(width: 8),
              badge,
            ],
          ),
          subtitle: Text(
            t.origin.first.display,
            style: origin,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(24, 0, 16, 10),
          children: [
            for (final frame in t.origin)
              _OriginRow(controller: controller, frame: frame, style: origin),
          ],
        );
      },
    );
  }
}

class _OriginRow extends StatelessWidget {
  const _OriginRow({
    required this.controller,
    required this.frame,
    required this.style,
  });

  final InspectorController controller;
  final OriginFrame frame;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (!frame.canOpen) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SelectableText(frame.display, style: style),
      );
    }
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => controller.openInEditor(frame),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                frame.display,
                style: style?.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            Tooltip(
              message: 'Open in editor',
              child: Icon(Icons.open_in_new, size: 12, color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel({required this.controller, required this.history});

  final InspectorController controller;
  final List<String> history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
    final last = history.length - 1;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: history.length,
      itemBuilder: (context, i) {
        final index = last - i;
        final isCurrent = index == last;
        return ListTile(
          dense: true,
          leading: _Badge(text: '#$index'),
          title: Text(history[index], style: mono),
          trailing: isCurrent
              ? const _Tag(text: 'current', tone: _Tone.neutral)
              : _WriteButton(
                  controller: controller,
                  icon: Icons.history,
                  label: 'Jump',
                  command: <String, Object?>{
                    'cmd': 'timeTravel',
                    'index': index,
                  },
                ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(fontFamily: 'monospace'),
      ),
    );
  }
}

enum _Tone { neutral, added }

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.tone});

  final String text;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (tone) {
      _Tone.added => theme.colorScheme.tertiary,
      _Tone.neutral => theme.colorScheme.outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
