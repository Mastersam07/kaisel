import 'package:flutter/material.dart';

import 'gate_guard.dart';
import 'gate_route.dart';
import 'gate_router.dart';
import 'gate_router_delegate.dart';

/// A multi-branch navigation state container.
///
/// Holds N independent [GateRouter]s — one per branch (tab) — plus an
/// active branch index. Each branch has its own stack and lifecycle.
/// Branches share the route type [R]; you constrain "what's valid on
/// which tab" through your pattern-matched [GatePageBuilder] and your
/// own discipline. (Per-branch typed routes are a v0.3 concern.)
class ShellRouter<R extends GateRoute> extends ChangeNotifier {
  /// Create a shell with one router per [branchInitials].
  ShellRouter({
    required List<R> branchInitials,
    int initialBranch = 0,
    List<GateGuard<R>> guards = const [],
  })  : assert(branchInitials.isNotEmpty,
            'A shell must have at least one branch.'),
        assert(initialBranch >= 0 && initialBranch < branchInitials.length,
            'initialBranch out of range'),
        _branches = [
          for (final initial in branchInitials)
            GateRouter<R>(initial: initial, guards: guards),
        ],
        _activeBranch = initialBranch {
    for (final branch in _branches) {
      branch.addListener(notifyListeners);
    }
  }

  final List<GateRouter<R>> _branches;
  int _activeBranch;

  /// Read-only view of the branch routers.
  List<GateRouter<R>> get branches => List.unmodifiable(_branches);

  /// Index of the currently selected branch.
  int get activeBranch => _activeBranch;

  /// The router for the currently selected branch.
  GateRouter<R> get current => _branches[_activeBranch];

  /// Number of branches.
  int get branchCount => _branches.length;

  /// Select a different branch. No-op if [branch] is already active.
  void switchTo(int branch) {
    if (branch < 0 || branch >= _branches.length) {
      throw RangeError.range(branch, 0, _branches.length - 1, 'branch');
    }
    if (branch == _activeBranch) return;
    _activeBranch = branch;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final branch in _branches) {
      branch.removeListener(notifyListeners);
      branch.dispose();
    }
    super.dispose();
  }
}

/// Signature for the chrome around a shell — typically a [Scaffold]
/// with a bottom nav bar — given the active branch index, the branch
/// content (an [IndexedStack] of nested navigators), and a callback
/// to switch branches.
typedef GateShellChromeBuilder = Widget Function(
  BuildContext context,
  int activeBranch,
  Widget branchContent,
  void Function(int branch) switchBranch,
);

/// Optional wrapper for each branch's content — typically used to
/// inject branch-scoped state (a `BlocProvider`, `ProviderScope`,
/// signals scope, etc.) that should live as long as the branch is
/// mounted. Called once per branch when the shell is built.
typedef GateBranchScope = Widget Function(
  BuildContext context,
  int branchIndex,
  Widget child,
);

/// A multi-branch navigation widget — what you reach for to build a
/// bottom-nav app with per-tab back stacks and scoped state.
///
/// Place a `GateShell` in your top-level builder as the screen for the
/// "main app" route variant:
///
/// ```dart
/// builder: (context, route) => switch (route) {
///   MainShell() => GateShell<AppRoute>(
///     branchInitials: const [HomeRoot(), DiscoverRoot(), ProfileRoot()],
///     pageBuilder: (context, route) => switch (route) {
///       HomeRoot() => const HomeScreen(),
///       DiscoverRoot() => const DiscoverScreen(),
///       ProfileRoot() => const ProfileScreen(),
///       ProductDetail(:final id) => ProductDetailScreen(id: id),
///       // ...all variants reachable from any branch...
///     },
///     chromeBuilder: (context, index, child, switchBranch) => Scaffold(
///       body: child,
///       bottomNavigationBar: NavigationBar(
///         selectedIndex: index,
///         onDestinationSelected: switchBranch,
///         destinations: const [...],
///       ),
///     ),
///   ),
///   Login() => const LoginScreen(),
/// },
/// ```
///
/// Inside any branch screen, get the branch's router via
/// `context.branchRouter<AppRoute>()` and the shell router via
/// `context.shellRouter<AppRoute>()`.
class GateShell<R extends GateRoute> extends StatefulWidget {
  /// Create a shell with [branchInitials.length] branches.
  const GateShell({
    super.key,
    required this.branchInitials,
    required this.pageBuilder,
    required this.chromeBuilder,
    this.initialBranch = 0,
    this.guards = const [],
    this.branchScope,
    this.pageWrapper,
  });

  /// One route per branch — the initial route for that branch's stack.
  final List<R> branchInitials;

  /// Resolves a route to a widget. The same builder is used across all
  /// branches, since they share the route type.
  final GatePageBuilder<R> pageBuilder;

  /// Builds the shell chrome around the active branch's content.
  final GateShellChromeBuilder chromeBuilder;

  /// Which branch is selected initially.
  final int initialBranch;

  /// Guards applied to every branch's router.
  final List<GateGuard<R>> guards;

  /// Optional per-branch wrapper. Called once per branch when the
  /// shell is built — wrap with `BlocProvider` / `ProviderScope` /
  /// signals containers, etc.
  final GateBranchScope? branchScope;

  /// Optional page wrapper — defaults to [MaterialPage].
  final GatePageWrapper<R>? pageWrapper;

  @override
  State<GateShell<R>> createState() => _GateShellState<R>();
}

class _GateShellState<R extends GateRoute> extends State<GateShell<R>> {
  late final ShellRouter<R> _shell;
  late final List<GlobalKey<NavigatorState>> _navKeys;

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
        GlobalKey<NavigatorState>(debugLabel: 'gate-branch-$i'),
    ];
    _shell.addListener(_onShellChange);
  }

  void _onShellChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
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
        if (didPop) return;
        if (activeRouter.canPop) {
          activeRouter.pop();
        }
      },
      child: ShellScope<R>(
        shellRouter: _shell,
        child: Builder(
          builder: (context) {
            final branchContent = IndexedStack(
              index: _shell.activeBranch,
              children: [
                for (var i = 0; i < _shell.branchCount; i++)
                  _buildBranch(context, i),
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
    );
  }

  Widget _buildBranch(BuildContext context, int index) {
    final router = _shell.branches[index];
    Widget content = _BranchNavigator<R>(
      router: router,
      navigatorKey: _navKeys[index],
      pageBuilder: widget.pageBuilder,
      pageWrapper: widget.pageWrapper,
    );
    final scope = widget.branchScope;
    if (scope != null) {
      content = scope(context, index, content);
    }
    return content;
  }
}

class _BranchNavigator<R extends GateRoute> extends StatefulWidget {
  const _BranchNavigator({
    required this.router,
    required this.navigatorKey,
    required this.pageBuilder,
    required this.pageWrapper,
  });

  final GateRouter<R> router;
  final GlobalKey<NavigatorState> navigatorKey;
  final GatePageBuilder<R> pageBuilder;
  final GatePageWrapper<R>? pageWrapper;

  @override
  State<_BranchNavigator<R>> createState() => _BranchNavigatorState<R>();
}

class _BranchNavigatorState<R extends GateRoute>
    extends State<_BranchNavigator<R>> {
  @override
  void initState() {
    super.initState();
    widget.router.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(_BranchNavigator<R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.router, widget.router)) {
      oldWidget.router.removeListener(_onChange);
      widget.router.addListener(_onChange);
    }
  }

  @override
  void dispose() {
    widget.router.removeListener(_onChange);
    super.dispose();
  }

  Page<Object?> _wrap(BuildContext context, R route, LocalKey key) {
    final wrapper = widget.pageWrapper;
    final child = Builder(
      builder: (innerContext) => widget.pageBuilder(innerContext, route),
    );
    if (wrapper != null) return wrapper(route, child, key);
    return MaterialPage<Object?>(key: key, child: child);
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: widget.navigatorKey,
      pages: [
        for (final entry in widget.router.entries)
          _wrap(context, entry.route, ValueKey<int>(entry.id)),
      ],
      onDidRemovePage: (page) {
        final key = page.key;
        if (key is ValueKey<int>) {
          widget.router.onPageRemoved(key.value);
        }
      },
    );
  }
}

/// Inherited widget exposing the [ShellRouter] to descendants.
///
/// Look up via [ShellScope.of] or, more conveniently, the
/// `context.shellRouter<R>()` and `context.branchRouter<R>()`
/// extensions.
class ShellScope<R extends GateRoute> extends InheritedWidget {
  /// Create a scope around [child] exposing [shellRouter].
  const ShellScope({
    super.key,
    required this.shellRouter,
    required super.child,
  });

  /// The shell router exposed at this scope.
  final ShellRouter<R> shellRouter;

  /// Look up the nearest [ShellScope] of route type [R].
  ///
  /// Throws if no scope is found — wrap your screen in a [GateShell]
  /// or use [maybeOf] if absence is expected.
  static ShellScope<R> of<R extends GateRoute>(BuildContext context) {
    final scope = maybeOf<R>(context);
    if (scope == null) {
      throw FlutterError(
        'ShellScope<$R> not found in widget tree.\n'
        'Ensure the calling widget is inside a GateShell<$R>.',
      );
    }
    return scope;
  }

  /// Like [of], but returns null instead of throwing.
  static ShellScope<R>? maybeOf<R extends GateRoute>(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope<R>>();

  @override
  bool updateShouldNotify(ShellScope<R> old) =>
      !identical(old.shellRouter, shellRouter);
}

/// Convenience accessors for shell-scoped routers.
extension GateBuildContextX on BuildContext {
  /// The router for the currently active branch in the enclosing
  /// [GateShell]. Use this in screens that need to push within their
  /// own tab.
  GateRouter<R> branchRouter<R extends GateRoute>() =>
      ShellScope.of<R>(this).shellRouter.current;

  /// The enclosing [ShellRouter]. Use this to switch tabs
  /// programmatically.
  ShellRouter<R> shellRouter<R extends GateRoute>() =>
      ShellScope.of<R>(this).shellRouter;
}
