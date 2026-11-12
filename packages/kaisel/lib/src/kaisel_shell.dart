import 'package:flutter/material.dart';
import 'package:kaisel_core/framework.dart';

import 'kaisel_adaptive.dart';
import 'kaisel_inner_navigator.dart';
import 'kaisel_module.dart';
import 'kaisel_page_wrapper.dart';
import 'kaisel_router_delegate.dart';
import 'kaisel_screen_signal.dart';
import 'kaisel_scope.dart';

/// A multi-branch navigation state container.
///
/// Holds N independent [KaiselRouter]s — one per branch (tab) — plus an
/// active branch index. Each branch has its own stack and lifecycle.
/// Branches share the route type [R]; you constrain "what's valid on
/// which tab" through your pattern-matched [KaiselPageBuilder] and your
/// own discipline. For per-branch typed routes, see [KaiselBranchedShell].
class ShellRouter<R extends KaiselRoute> extends ChangeNotifier
    implements KaiselNestedHandle, KaiselShellController {
  /// Create a shell with one router per [branchInitials].
  ShellRouter({
    required List<R> branchInitials,
    int initialBranch = 0,
    List<KaiselGuard<R>> guards = const [],
  }) : assert(
         branchInitials.isNotEmpty,
         'A shell must have at least one branch.',
       ),
       assert(
         initialBranch >= 0 && initialBranch < branchInitials.length,
         'initialBranch out of range',
       ),
       _branches = [
         for (final initial in branchInitials)
           KaiselRouter<R>(initial: initial, guards: guards),
       ],
       _activeBranch = initialBranch {
    for (var i = 0; i < _branches.length; i++) {
      void listener() => _onBranchChanged(i);
      _branchListeners.add(listener);
      _branches[i].addListener(listener);
    }
  }

  final List<KaiselRouter<R>> _branches;
  final List<VoidCallback> _branchListeners = [];
  int _activeBranch;
  bool _replacesHistoryEntry = false;

  void _onBranchChanged(int i) {
    if (i == _activeBranch) {
      _replacesHistoryEntry = current.replacesHistoryEntry;
    }
    notifyListeners();
  }

  /// Whether the active branch's most recent change should overwrite the
  /// browser history entry rather than add one. A branch switch resets it to
  /// `false` (selecting a tab adds an entry).
  @override
  bool get replacesHistoryEntry => _replacesHistoryEntry;

  /// Read-only view of the branch routers.
  List<KaiselRouter<R>> get branches => List.unmodifiable(_branches);

  /// Index of the currently selected branch.
  @override
  int get activeBranch => _activeBranch;

  /// The router for the currently selected branch.
  @override
  KaiselRouter<R> get current => _branches[_activeBranch];

  /// Number of branches.
  @override
  int get branchCount => _branches.length;

  /// Select a different branch. No-op if [branch] is already active.
  @override
  void switchTo(int branch) {
    if (branch < 0 || branch >= _branches.length) {
      throw RangeError.range(branch, 0, _branches.length - 1, 'branch');
    }
    if (branch == _activeBranch) return;
    _activeBranch = branch;
    _replacesHistoryEntry = false;
    notifyListeners();
  }

  @override
  Type get configType => KaiselShellConfig;

  @override
  KaiselShellConfig captureConfig() => KaiselShellConfig(
    activeBranch: _activeBranch,
    activeBranchStack: current.stack,
  );

  @override
  Future<void> restoreFromConfig(KaiselNestedConfig config) async {
    if (config is! KaiselShellConfig) return;
    // A restored config is external input: a deep link can name a branch this
    // build doesn't mount. Skip it rather than throw.
    if (config.activeBranch < 0 || config.activeBranch >= _branches.length) {
      assert(() {
        debugPrint(
          'kaisel: ignoring restored shell branch ${config.activeBranch} — '
          'this shell mounts ${_branches.length} '
          'branch${_branches.length == 1 ? '' : 'es'} '
          '(0..${_branches.length - 1}). The deep link or codec targets a '
          'branch that does not exist on this build.',
        );
        return true;
      }());
      return;
    }
    await _branches[config.activeBranch].restoreStack(config.activeBranchStack);
    if (config.activeBranch != _activeBranch) {
      _activeBranch = config.activeBranch;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (var i = 0; i < _branches.length; i++) {
      _branches[i]
        ..removeListener(_branchListeners[i])
        ..dispose();
    }
    super.dispose();
  }
}

/// Signature for the chrome around a shell — typically a [Scaffold]
/// with a bottom nav bar — given the active branch index, the branch
/// content (an [IndexedStack] of nested navigators), and a callback
/// to switch branches.
typedef KaiselShellChromeBuilder =
    Widget Function(
      BuildContext context,
      int activeBranch,
      Widget branchContent,
      void Function(int branch) switchBranch,
    );

/// Optional wrapper for each branch's content — typically used to
/// inject branch-scoped state (a `BlocProvider`, `ProviderScope`,
/// signals scope, etc.) that should live as long as the branch is
/// mounted. Called once per branch when the shell is built.
typedef KaiselBranchScope =
    Widget Function(BuildContext context, int branchIndex, Widget child);

/// A multi-branch navigation widget — what you reach for to build a
/// bottom-nav app with per-tab back stacks and scoped state.
///
/// Place a `KaiselShell` in your top-level builder as the screen for the
/// "main app" route variant. Inside any branch screen, get the branch's
/// router via `context.router<AppRoute>()` (which resolves to the
/// active branch's router when inside a shell) and the shell controller
/// via `context.shell()`.
class KaiselShell<R extends KaiselRoute> extends StatefulWidget {
  /// Create a shell with [branchInitials.length] branches using a
  /// simple per-route page builder.
  const KaiselShell({
    super.key,
    required this.branchInitials,
    required KaiselPageBuilder<R> pageBuilder,
    required this.chromeBuilder,
    this.initialBranch = 0,
    this.guards = const [],
    this.branchScope,
    this.pageWrapper,
    this.rootBackArrow = true,
  }) : _pageBuilder = pageBuilder,
       _adaptivePageBuilder = null;

  /// Create a shell whose branches use an adaptive page builder.
  /// The builder receives a [KaiselStackContext] for each entry so it
  /// can return [KaiselAbsorbingPage] to collapse the master into the
  /// detail at wide breakpoints.
  ///
  /// All branches share the adaptive builder (the route type is
  /// the same across branches in [KaiselShell]). For per-branch
  /// adaptive configuration use [KaiselBranchedShell] with
  /// [KaiselBranch.adaptive].
  const KaiselShell.adaptive({
    super.key,
    required this.branchInitials,
    required KaiselAdaptivePageBuilder<R> pageBuilder,
    required this.chromeBuilder,
    this.initialBranch = 0,
    this.guards = const [],
    this.branchScope,
    this.pageWrapper,
    this.rootBackArrow = true,
  }) : _pageBuilder = null,
       _adaptivePageBuilder = pageBuilder;

  /// One route per branch. The initial route for that branch's stack.
  final List<R> branchInitials;

  final KaiselPageBuilder<R>? _pageBuilder;
  final KaiselAdaptivePageBuilder<R>? _adaptivePageBuilder;

  /// Builds the shell chrome around the active branch's content.
  final KaiselShellChromeBuilder chromeBuilder;

  /// Which branch is selected initially.
  final int initialBranch;

  /// Guards applied to every branch's router.
  final List<KaiselGuard<R>> guards;

  /// Optional per-branch wrapper. Called once per branch when the
  /// shell is built. Wrap with `BlocProvider` / `ProviderScope` /
  /// signals containers, etc.
  final KaiselBranchScope? branchScope;

  /// Optional page wrapper. Defaults to [MaterialPage].
  final KaiselPageWrapper<R>? pageWrapper;

  /// Whether the first screen of each branch shows an `AppBar` back arrow
  /// that leaves the shell when there's a page below it. Defaults to true, so
  /// the arrow matches what system back does. Pass false to keep the first
  /// screens without an implied back arrow.
  final bool rootBackArrow;

  @override
  State<KaiselShell<R>> createState() => _KaiselShellState<R>();
}

bool _nestedUnderAnotherRouter(BuildContext context) {
  var nested = false;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    nested =
        widget is KaiselShellScope ||
        widget is FlowScope ||
        widget is KaiselModuleMount;
    return !nested;
  });
  return nested;
}

class _KaiselShellState<R extends KaiselRoute> extends State<KaiselShell<R>> {
  late final ShellRouter<R> _shell;
  late final List<GlobalKey<NavigatorState>> _navKeys;
  KaiselNestedHost? _host;

  @override
  void initState() {
    super.initState();
    _shell = ShellRouter<R>(
      branchInitials: widget.branchInitials,
      initialBranch: widget.initialBranch,
      guards: widget.guards,
    );
    _navKeys = [
      for (var i = 0; i < widget.branchInitials.length; i++)
        GlobalKey<NavigatorState>(debugLabel: 'kaisel-branch-$i'),
    ];
    _shell.addListener(_onShellChange);
    _lastBranch = _shell.activeBranch;
    _lastActiveTop = _activeTop();
  }

  late int _lastBranch;
  KaiselRoute? _lastActiveTop;
  KaiselObserversBuilder? _switchObserversBuilder;
  KaiselScreenReporter? _screenReporter;
  List<NavigatorObserver> _switchObservers = const [];

  KaiselRoute? _activeTop() {
    final stack = _shell.current.stack;
    return stack.isEmpty ? null : stack.last;
  }

  void _onShellChange() {
    final branch = _shell.activeBranch;
    final top = _activeTop();
    if (branch != _lastBranch) {
      final from = _lastActiveTop;
      if (from != null && top != null && from != top) {
        kaiselReportSyntheticReplace(
          changes: [(from, top)],
          observers: _switchObservers,
        );
      }
    }
    _lastBranch = branch;
    _lastActiveTop = top;
    _screenReporter?.reportRoute(top);
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Registering lets the URL and restoration carry the active branch's
    // stack, as KaiselBranchedShell does. The URL holds one nested router, so
    // a shell under another shell, a module or a flow stays out of it and
    // leaves the URL to the router it sits in.
    final host = _nestedUnderAnotherRouter(context)
        ? null
        : KaiselNestedHostScope.maybeOf(context);
    if (!identical(host, _host)) {
      _host?.unregisterNested(_shell);
      _host = host;
      _host?.registerNested(_shell);
    }
    final builder = KaiselObserverScope.of(context);
    if (!identical(builder, _switchObserversBuilder)) {
      _switchObserversBuilder = builder;
      _switchObservers = builder?.call() ?? const <NavigatorObserver>[];
    }
    _screenReporter = KaiselObserverScope.reporterOf(context);
    _screenReporter?.reportRoute(_activeTop());
  }

  @override
  void dispose() {
    _host?.unregisterNested(_shell);
    _shell
      ..removeListener(_onShellChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeRouter = _shell.current;

    // canPop is from the parent's perspective: if the branch has its
    // own history to unwind, the parent must NOT pop the shell — we
    // handle the back in-shell. Once the branch is at root, let the
    // parent pop the shell.
    return PopScope(
      canPop: !activeRouter.canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || kaiselHasOpenOverlay(activeRouter)) return;
        if (activeRouter.canPop) {
          activeRouter.pop();
        }
      },
      child: KaiselShellScope(
        controller: _shell,
        child: ShellChromeScope(
          child: Builder(
            builder: (context) {
              final branchContent = IndexedStack(
                index: _shell.activeBranch,
                children: [
                  for (var i = 0; i < _shell.branchCount; i++)
                    TickerMode(
                      enabled: i == _shell.activeBranch,
                      child: _buildBranch(context, i),
                    ),
                ],
              );
              return widget.chromeBuilder(
                context,
                _shell.activeBranch,
                branchContent,
                _shell.switchTo,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBranch(BuildContext context, int index) {
    final router = _shell.branches[index];
    Widget content = KaiselInnerNavigator<R>(
      router: router,
      navigatorKey: _navKeys[index],
      pageBuilder: widget._pageBuilder,
      adaptivePageBuilder: widget._adaptivePageBuilder,
      pageWrapper: widget.pageWrapper,
      rootPopsParent: widget.rootBackArrow,
      closesOverlaysOnBack: true,
    );
    final scope = widget.branchScope;
    if (scope != null) {
      content = scope(context, index, content);
    }
    // Each branch installs its own RouterScope so context.router<R>()
    // inside a branch screen resolves to that branch's router, and its own
    // restoration scope so the branch's pages restore independently.
    return KaiselRestorationScope(
      restorationId: 'kaisel-branch-$index',
      child: RouterScope<R>(router: router, child: content),
    );
  }
}
