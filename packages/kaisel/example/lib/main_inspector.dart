// DevTools inspector playground.
//
// One app that exercises every feature the kaisel DevTools extension
// surfaces, so you can watch each panel update live. Run:
//
//   flutter run -t lib/main_inspector.dart
//
// then open DevTools → the "kaisel" tab and drive it from the Hub screen.
// Use a WIDE window (desktop / iPad / Chrome) so the Inbox shows its
// adaptive master-detail layout.
//
// What it exercises
// -----------------
//  - Main stack            — every Hub button pushes/pops the main router.
//  - Branched shell         — "Open shell" mounts a 2-branch shell (Feed +
//                             Inbox). Inbox is adaptive master-detail.
//  - Modules                — "Open checkout" mounts a module with its own
//                             URL codec.
//  - Modal flows (nested)   — "Run confirm flow" opens a flow; from inside it
//                             you can open a second, nested flow.
//  - Guard trace            — "Go to Locked" is rewritten by a guard; the
//                             Guards panel shows the redirect.
//  - Codec / URL            — every state encodes to a URL (URL panel).
//  - No-op / missing props  — the Inbox tab has TWO kinds of message detail:
//                             a Correct one (overrides `props`) and a Buggy
//                             one (missing `props`). In master-detail, open a
//                             *Buggy* message, then tap another Buggy message:
//                             the detail does NOT change (pushOrReplaceTop is a
//                             no-op because the routes are value-equal). The
//                             inspector shows an empty diff — exactly the bug.
//                             The Correct rows switch fine, for contrast.

import 'package:flutter/material.dart';
import 'package:kaisel/kaisel.dart';

const _wide = 700.0;

// ── Main routes (main router) ──

sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

final class Hub extends AppRoute {
  const Hub();
}

final class AppShell extends AppRoute {
  const AppShell();
}

final class CheckoutMount extends AppRoute {
  const CheckoutMount();
}

/// A guard rewrites any navigation to this away — see [_lockGuard].
final class Locked extends AppRoute {
  const Locked();
}

/// A modal flow returning a bool.
final class ConfirmFlow extends AppRoute implements KaiselModalRoute<bool> {
  const ConfirmFlow();
}

/// A second modal flow, opened from inside [ConfirmFlow] to show nesting.
final class InfoFlow extends AppRoute implements KaiselModalRoute<void> {
  const InfoFlow();
}

// ── Branch routes ──

sealed class FeedRoute extends KaiselRoute {
  const FeedRoute();
}

final class FeedList extends FeedRoute {
  const FeedList();
}

final class FeedPost extends FeedRoute {
  const FeedPost(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

sealed class InboxRoute extends KaiselRoute {
  const InboxRoute();
}

final class InboxList extends InboxRoute {
  const InboxList();
}

/// Correct message detail: overrides [props], so `pushOrReplaceTop` to a new
/// id actually switches the detail.
final class MessageDetail extends InboxRoute {
  const MessageDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

/// Buggy message detail: has an [id] field but NO `props` override, so every
/// `BuggyMessageDetail` is value-equal. In adaptive master-detail, opening one
/// and then tapping another in the list is a `pushOrReplaceTop` no-op — the
/// detail pane never changes. This is the real-world missing-`props` bug.
final class BuggyMessageDetail extends InboxRoute {
  const BuggyMessageDetail(this.id);
  final String id;
}

// ── Module routes ──

sealed class CheckoutRoute extends KaiselRoute {
  const CheckoutRoute();
}

final class Cart extends CheckoutRoute {
  const Cart();
}

final class Shipping extends CheckoutRoute {
  const Shipping();
}

final class PlaceOrder extends CheckoutRoute {
  const PlaceOrder();
}

class CheckoutModule extends RouteModule<CheckoutRoute> {
  const CheckoutModule();

  @override
  List<CheckoutRoute> get initialStack => const [Cart()];

  @override
  Widget buildPage(BuildContext context, CheckoutRoute route) =>
      switch (route) {
        Cart() => _ModuleStep(
          title: 'Cart',
          next: const Shipping(),
          nextLabel: 'To shipping',
        ),
        Shipping() => _ModuleStep(
          title: 'Shipping',
          next: const PlaceOrder(),
          nextLabel: 'Review',
        ),
        PlaceOrder() => const _ModuleStep(title: 'Place order'),
      };

  @override
  ModuleStackCodec<CheckoutRoute>? get codec => const _CheckoutCodec();
}

class _CheckoutCodec extends ModuleStackCodec<CheckoutRoute> {
  const _CheckoutCodec();

  @override
  List<String> encode(List<CheckoutRoute> stack) => switch (stack.last) {
    Cart() => const [],
    Shipping() => const ['shipping'],
    PlaceOrder() => const ['confirm'],
  };

  @override
  List<CheckoutRoute>? decode(List<String> segments) => switch (segments) {
    [] => const [Cart()],
    ['shipping'] => const [Cart(), Shipping()],
    ['confirm'] => const [Cart(), Shipping(), PlaceOrder()],
    _ => null,
  };
}

// ── Guards (main router) ──

List<AppRoute> _passthroughGuard(List<AppRoute> current, List<AppRoute> next) =>
    next;

List<AppRoute> _lockGuard(List<AppRoute> current, List<AppRoute> next) =>
    (next.isNotEmpty && next.last is Locked) ? const [Hub()] : next;

// ── Codec / URL ──

class _AppCodec implements KaiselConfigCodec<AppRoute> {
  const _AppCodec();

  @override
  Uri encode(KaiselConfig<AppRoute> config) {
    final base = config.mainStack
        .where((r) => r is! ConfirmFlow && r is! InfoFlow)
        .toList();
    final top = base.isEmpty ? const Hub() : base.last;
    return switch ((top, config.nestedState)) {
      (Hub(), _) => Uri(path: '/'),
      (Locked(), _) => Uri(path: '/locked'),
      (AppShell(), final KaiselShellConfig shell) => _encodeShell(shell),
      (AppShell(), _) => Uri(path: '/app/feed'),
      (CheckoutMount(), _) => Uri(path: '/checkout'),
      (ConfirmFlow() || InfoFlow(), _) => Uri(path: '/'),
    };
  }

  Uri _encodeShell(KaiselShellConfig shell) {
    final stack = shell.activeBranchStack;
    return switch (shell.activeBranch) {
      0 => switch (stack) {
        [FeedList(), FeedPost(:final id)] => Uri(path: '/app/feed/$id'),
        _ => Uri(path: '/app/feed'),
      },
      _ => switch (stack) {
        [InboxList(), MessageDetail(:final id)] => Uri(path: '/app/inbox/$id'),
        [InboxList(), BuggyMessageDetail(:final id)] => Uri(
          path: '/app/inbox/bug/$id',
        ),
        _ => Uri(path: '/app/inbox'),
      },
    };
  }

  @override
  KaiselConfig<AppRoute>? decode(Uri uri) {
    return switch (uri.pathSegments) {
      [] || [''] => KaiselConfig(mainStack: const [Hub()]),
      ['locked'] => KaiselConfig(mainStack: const [Hub(), Locked()]),
      ['app', 'feed'] => _shell(0, const [FeedList()]),
      ['app', 'feed', final id] => _shell(0, [const FeedList(), FeedPost(id)]),
      ['app', 'inbox'] => _shell(1, const [InboxList()]),
      ['app', 'inbox', 'bug', final id] => _shell(1, [
        const InboxList(),
        BuggyMessageDetail(id),
      ]),
      ['app', 'inbox', final id] => _shell(1, [
        const InboxList(),
        MessageDetail(id),
      ]),
      _ => null,
    };
  }

  KaiselConfig<AppRoute> _shell(int branch, List<KaiselRoute> stack) =>
      KaiselConfig(
        mainStack: const [AppShell()],
        nestedState: KaiselShellConfig(
          activeBranch: branch,
          activeBranchStack: stack,
        ),
      );
}

const _appCodec = ConfigCodecWithModules<AppRoute>(
  baseCodec: _AppCodec(),
  modules: [
    ModuleMount(
      mountRoute: CheckoutMount(),
      prefix: '/checkout',
      codec: _CheckoutCodec(),
    ),
  ],
);

// ── Wire-up ──

final _config = KaiselRouterConfig<AppRoute>(
  initial: const Hub(),
  guards: [_passthroughGuard, _lockGuard],
  builder: _buildMain,
  modalBuilder: _buildModal,
  codec: _appCodec,
  fallback: const [Hub()],
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp.router(
      title: 'kaisel inspector playground',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      routerConfig: _config,
    ),
  );
}

Widget _buildMain(BuildContext context, AppRoute route) => switch (route) {
  Hub() => const _HubScreen(),
  AppShell() => const _ShellHost(),
  CheckoutMount() => const KaiselModuleMount<CheckoutRoute>(
    module: CheckoutModule(),
  ),
  Locked() => const _Plain(
    'Locked — you should never see this; the guard redirects to the Hub.',
  ),
  ConfirmFlow() => const _ConfirmFlowScreen(),
  InfoFlow() => const _InfoFlowScreen(),
};

Widget _buildModal(
  BuildContext context,
  KaiselModalRoute<Object?> route,
  Widget flowChild,
) {
  return Material(
    color: Colors.black54,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Material(
            clipBehavior: Clip.hardEdge,
            borderRadius: BorderRadius.circular(16),
            child: flowChild,
          ),
        ),
      ),
    ),
  );
}

// ── Hub control panel ──

class _HubScreen extends StatelessWidget {
  const _HubScreen();

  KaiselRouter<AppRoute> get _router => _config.router;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inspector Playground · Hub')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Group('Shell · Modules', [
            _btn(
              'Open shell (Feed + adaptive Inbox)',
              () => _router.push(const AppShell()),
            ),
            _btn(
              'Open checkout module',
              () => _router.push(const CheckoutMount()),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Tip: in the Inbox tab (wide window), the "Buggy" messages '
                'show the missing-props no-op in master-detail.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ]),
          _Group('Modal flows', [
            _btn(
              'Run confirm flow (nested inside)',
              () => _router.run(const ConfirmFlow()),
            ),
          ]),
          _Group('Guards', [
            _btn(
              'Go to Locked (guard redirects → see Guards panel)',
              () => _router.push(const Locked()),
            ),
          ]),
        ],
      ),
    );
  }

  static Widget _btn(String label, VoidCallback onPressed) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: FilledButton.tonal(onPressed: onPressed, child: Text(label)),
  );
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.children);
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Plain extends StatelessWidget {
  const _Plain(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    ),
  );
}

// ── Shell (Feed + adaptive Inbox) ──

class _ShellHost extends StatefulWidget {
  const _ShellHost();
  @override
  State<_ShellHost> createState() => _ShellHostState();
}

class _ShellHostState extends State<_ShellHost> {
  late final KaiselRouter<FeedRoute> _feed = KaiselRouter<FeedRoute>(
    initial: const FeedList(),
  );
  late final KaiselRouter<InboxRoute> _inbox = KaiselRouter<InboxRoute>(
    initial: const InboxList(),
  );
  late final BranchedShellRouter _shell = BranchedShellRouter(
    branches: [_feed, _inbox],
  );

  @override
  void dispose() {
    _shell.dispose();
    _feed.dispose();
    _inbox.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KaiselBranchedShell(
      shell: _shell,
      branches: [
        KaiselBranch<FeedRoute>(
          router: _feed,
          pageBuilder: (context, route) => switch (route) {
            FeedList() => const _FeedListScreen(),
            FeedPost(:final id) => _Plain('Feed post $id'),
          },
        ),
        KaiselBranch<InboxRoute>.adaptive(
          router: _inbox,
          pageBuilder: _inboxAdaptive,
        ),
      ],
      chromeBuilder: (context, active, branchContent, switchBranch) {
        return Scaffold(
          body: branchContent,
          bottomNavigationBar: NavigationBar(
            selectedIndex: active,
            onDestinationSelected: switchBranch,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dynamic_feed),
                label: 'Feed',
              ),
              NavigationDestination(icon: Icon(Icons.inbox), label: 'Inbox'),
            ],
          ),
        );
      },
    );
  }
}

KaiselPageResult _inboxAdaptive(
  BuildContext context,
  InboxRoute route,
  KaiselStackContext<InboxRoute> ctx,
) {
  final wide = MediaQuery.of(context).size.width >= _wide;
  return switch ((ctx.previous, route, wide)) {
    (_, InboxList(), _) => const KaiselStandalonePage(_InboxListScreen()),
    (InboxList(), MessageDetail(:final id), true) => KaiselAbsorbingPage(
      widget: KaiselMasterDetailScaffold(
        master: _InboxListScreen(selectedId: id, selectedBuggy: false),
        detail: _MessageScreen(id: id, buggy: false, showBack: false),
      ),
      absorbing: 1,
    ),
    (InboxList(), BuggyMessageDetail(:final id), true) => KaiselAbsorbingPage(
      widget: KaiselMasterDetailScaffold(
        master: _InboxListScreen(selectedId: id, selectedBuggy: true),
        detail: _MessageScreen(id: id, buggy: true, showBack: false),
      ),
      absorbing: 1,
    ),
    (_, MessageDetail(:final id), _) => KaiselStandalonePage(
      _MessageScreen(id: id, buggy: false),
    ),
    (_, BuggyMessageDetail(:final id), _) => KaiselStandalonePage(
      _MessageScreen(id: id, buggy: true),
    ),
  };
}

class _FeedListScreen extends StatelessWidget {
  const _FeedListScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feed')),
      body: ListView(
        children: [
          for (final id in ['p1', 'p2', 'p3'])
            ListTile(
              title: Text('Post $id'),
              onTap: () => context.router<FeedRoute>().push(FeedPost(id)),
            ),
        ],
      ),
    );
  }
}

class _InboxListScreen extends StatelessWidget {
  const _InboxListScreen({this.selectedId, this.selectedBuggy = false});
  final String? selectedId;
  final bool selectedBuggy;

  @override
  Widget build(BuildContext context) {
    const ids = ['m1', 'm2', 'm3'];
    return Scaffold(
      appBar: AppBar(title: const Text('Inbox')),
      body: ListView(
        children: [
          const _SectionHeader('Correct — has props (switching works)'),
          for (final id in ids)
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              selected: !selectedBuggy && id == selectedId,
              title: Text('Message $id'),
              onTap: () => context.router<InboxRoute>().pushOrReplaceTop(
                MessageDetail(id),
                when: (top) =>
                    top is MessageDetail || top is BuggyMessageDetail,
              ),
            ),
          const Divider(),
          const _SectionHeader('Buggy — missing props (switch is a NO-OP)'),
          for (final id in ids)
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              selected: selectedBuggy && id == selectedId,
              title: Text('Message $id'),
              subtitle: const Text('open one, then tap another → no change'),
              onTap: () => context.router<InboxRoute>().pushOrReplaceTop(
                BuggyMessageDetail(id),
                when: (top) =>
                    top is MessageDetail || top is BuggyMessageDetail,
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: Theme.of(context).hintColor),
      ),
    );
  }
}

class _MessageScreen extends StatelessWidget {
  const _MessageScreen({
    required this.id,
    required this.buggy,
    this.showBack = true,
  });
  final String id;
  final bool buggy;
  final bool showBack;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: showBack,
        title: Text('${buggy ? "Buggy " : ""}Message $id'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Body of message $id'),
            if (buggy) ...[
              const SizedBox(height: 12),
              const Text(
                'Tap another "Buggy" message in the list — this pane will '
                'NOT change (the route is missing props).',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Flow screens ──

class _ConfirmFlowScreen extends StatelessWidget {
  const _ConfirmFlowScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm?'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: context.dismissFlow,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('A modal flow on the main router.'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _config.router.run(const InfoFlow()),
              child: const Text('Open nested info flow'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => context.completeFlow<bool>(true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoFlowScreen extends StatelessWidget {
  const _InfoFlowScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nested info')),
      body: Center(
        child: FilledButton(
          onPressed: () => context.completeFlow<void>(null),
          child: const Text('Close'),
        ),
      ),
    );
  }
}

// ── Module step screen ──

class _ModuleStep extends StatelessWidget {
  const _ModuleStep({required this.title, this.next, this.nextLabel});
  final String title;
  final CheckoutRoute? next;
  final String? nextLabel;
  @override
  Widget build(BuildContext context) {
    final next = this.next;
    return Scaffold(
      appBar: AppBar(title: Text('Checkout · $title')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            if (next != null && nextLabel != null)
              FilledButton(
                onPressed: () => context.router<CheckoutRoute>().push(next),
                child: Text(nextLabel!),
              )
            else
              FilledButton(
                onPressed: () => context.router<AppRoute>().pop(),
                child: const Text('Finish (exit module)'),
              ),
            TextButton(
              onPressed: () => context.router<AppRoute>().pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
