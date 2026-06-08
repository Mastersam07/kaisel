import 'package:flutter/material.dart';

import 'inspector_controller.dart';
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

class _RootView extends StatelessWidget {
  const _RootView({
    required this.root,
    required this.previous,
    required this.transitions,
  });

  final RootSnapshot root;
  final RootSnapshot? previous;
  final List<Transition> transitions;

  @override
  Widget build(BuildContext context) {
    final previousMainIds = <int>{
      for (final entry in previous?.main.entries ?? const <EntrySnapshot>[])
        entry.id,
    };

    // Tabs are built dynamically: shells / flows / modules only appear when
    // present, so the bar stays uncluttered for a plain app.
    final tabs = <(String, Widget)>[
      ('Stack', _StackList(stack: root.main, previousIds: previousMainIds)),
      if (root.branches.isNotEmpty)
        ('Shells', _BranchesPanel(shells: root.branches)),
      if (root.flows.isNotEmpty) ('Flows', _FlowsPanel(flows: root.flows)),
      if (root.modules.isNotEmpty)
        ('Modules', _ModulesPanel(modules: root.modules)),
      if (root.problems.isNotEmpty)
        (
          'Problems (${root.problems.length})',
          _ProblemsPanel(problems: root.problems),
        ),
      ('Guards', _GuardPanel(trace: root.guardTrace)),
      ('URL', _UrlPanel(root: root)),
      if (transitions.isNotEmpty)
        (
          'Log (${transitions.length})',
          _TransitionsPanel(transitions: transitions),
        ),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(root: root),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final (label, _) in tabs) Tab(text: label)],
          ),
          Expanded(
            child: TabBarView(
              children: [for (final (_, widget) in tabs) widget],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.root});

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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          Icon(
            Icons.account_tree_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(root.id, style: theme.textTheme.titleSmall),
          const Spacer(),
          Text(parts.join('  ·  '), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _StackList extends StatelessWidget {
  const _StackList({required this.stack, this.previousIds});

  final StackSnapshot stack;

  /// Entry ids present in the previous snapshot. When non-null, entries whose
  /// id is absent are highlighted as newly pushed. Pass null to disable diff
  /// highlighting (e.g. for branch stacks, whose ids are positional).
  final Set<int>? previousIds;

  @override
  Widget build(BuildContext context) {
    if (stack.entries.isEmpty) return const _Message('Empty.');
    final ordered = stack.entries.reversed.toList();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: ordered.length,
      itemBuilder: (context, i) {
        final entry = ordered[i];
        final isTop = i == 0;
        final isNew = previousIds != null && !previousIds!.contains(entry.id);
        return _EntryTile(entry: entry, isTop: isTop, isNew: isNew);
      },
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
            if (isTop) const _Tag(text: 'top', tone: _Tone.neutral),
            if (isNew) const _Tag(text: 'new', tone: _Tone.added),
          ],
        ),
      ),
    );
  }
}

class _BranchesPanel extends StatelessWidget {
  const _BranchesPanel({required this.shells});

  final List<ShellSnapshot> shells;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final shell in shells) ...[
          Text(
            '${shell.type}  ·  branch ${shell.activeBranch} / ${shell.branchCount}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          for (final branch in shell.branches)
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
                        if (branch.index == shell.activeBranch)
                          const _Tag(text: 'active', tone: _Tone.added),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _MiniStack(stack: branch.stack),
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
  const _FlowsPanel({required this.flows});

  final List<FlowSnapshot> flows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
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
              '${i == 0 ? '▸ ' : '  '}${ordered[i].label}',
              style: i == 0
                  ? mono?.copyWith(fontWeight: FontWeight.bold)
                  : mono,
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

class _UrlPanel extends StatelessWidget {
  const _UrlPanel({required this.root});

  final RootSnapshot root;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = root.url;
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
      ],
    );
  }
}

class _TransitionsPanel extends StatelessWidget {
  const _TransitionsPanel({required this.transitions});

  final List<Transition> transitions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: transitions.length,
      itemBuilder: (context, i) {
        final t = transitions[i];
        final noOp = t.op == 'no-op';
        return ListTile(
          dense: true,
          leading: _Tag(text: t.op, tone: noOp ? _Tone.added : _Tone.neutral),
          title: Text(t.label, style: mono),
          trailing: _Badge(text: t.router),
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
