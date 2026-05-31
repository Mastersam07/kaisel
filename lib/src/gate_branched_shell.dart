import 'package:flutter/material.dart';

import 'gate_adaptive.dart';
import 'gate_config.dart';
import 'gate_inner_navigator.dart';
import 'gate_page_wrapper.dart';
import 'gate_route.dart';
import 'gate_router.dart';
import 'gate_router_delegate.dart';
import 'gate_scope.dart';

/// Aggregator for a shell whose branches have **different** route types.
///
/// Where [ShellRouter] (v0.2 / v0.3) requires every branch to share a
/// single route type, `BranchedShellRouter` lets you keep one sealed
/// type per branch and have the compiler enforce that you never push
/// a `DiscoverRoute` into the Home tab:
///
/// ```dart
/// sealed class HomeRoute extends GateRoute { const HomeRoute(); }
/// sealed class DiscoverRoute extends GateRoute { const DiscoverRoute(); }
///
/// final homeRouter = GateRouter<HomeRoute>(initial: const HomeRoot());
/// final discoverRouter = GateRouter<DiscoverRoute>(initial: const DiscoverRoot());
///
/// final shell = BranchedShellRouter(
///   branches: [homeRouter, discoverRouter],
/// );
/// ```
///
/// The shell holds the routers as [GateNavigator] (the non-generic
/// slice of [GateRouter]) so the list can be heterogeneous — Dart
/// generics are invariant in [GateRouter]'s type parameter, so a typed
/// list is not possible. The shell uses only non-generic operations
/// (can-pop and pop on the active branch for back handling); typed
/// pushes happen on the user's own typed router references, or via
/// `context.router<BranchR>()` inside a branch screen.
class BranchedShellRouter extends ChangeNotifier implements GateNestedHandle {
  /// Create a shell aggregating [branches]. Each entry is typically a
  /// `GateRouter<BranchR>` for some sealed `BranchR`.
  BranchedShellRouter({
    required List<GateNavigator> branches,
    int initialBranch = 0,
  })  : assert(branches.isNotEmpty, 'A shell must have at least one branch.'),
        assert(
          initialBranch >= 0 && initialBranch < branches.length,
          'initialBranch out of range',
        ),
        _branches = List<GateNavigator>.unmodifiable(branches),
        _activeBranch = initialBranch {
    for (final branch in _branches) {
      branch.addListener(notifyListeners);
    }
  }

  final List<GateNavigator> _branches;
  int _activeBranch;

  /// The branches, as a non-generic view. Use your own typed
  /// references to access type-safe navigation methods.
  List<GateNavigator> get branches => _branches;

  /// Index of the currently selected branch.
  int get activeBranch => _activeBranch;

  /// The currently selected branch (as the non-generic view).
  GateNavigator get current => _branches[_activeBranch];

  /// Number of branches.
  int get branchCount => _branches.length;

  /// Whether `pop` on the active branch would remove a route.
  bool get currentCanPop => current.canPop;

  /// Pop on the active branch. Equivalent to `current.pop()` but
  /// expressed as an instance method for clarity at call sites.
  Future<bool> popCurrent() => current.pop();

  /// Select a different branch. No-op if [branch] is already active.
  void switchTo(int branch) {
    if (branch < 0 || branch >= _branches.length) {
      throw RangeError.range(branch, 0, _branches.length - 1, 'branch');
    }
    if (branch == _activeBranch) return;
    _activeBranch = branch;
    notifyListeners();
  }

  // Capture/restore is the bridge between the shell's runtime state
  // and the URL. captureConfig describes what's currently visible;
  // restoreFromConfig replays a captured snapshot. The host filters
  // by configType before calling, but a defensive `is` check inside
  // restoreFromConfig protects against direct misuse.

  @override
  Type get configType => GateShellConfig;

  @override
  GateShellConfig captureConfig() {
    return GateShellConfig(
      activeBranch: _activeBranch,
      activeBranchStack: current.stack,
    );
  }

  @override
  Future<void> restoreFromConfig(GateNestedConfig config) async {
    if (config is! GateShellConfig) return;
    if (config.activeBranch < 0 || config.activeBranch >= _branches.length) {
      throw RangeError.range(
        config.activeBranch,
        0,
        _branches.length - 1,
        'config.activeBranch',
      );
    }
    // Restore the target branch's stack first so when we switch to it
    // the UI is already in the right state. Inactive branches are
    // deliberately left alone — their in-memory state is the user's
    // history within those tabs.
    await _branches[config.activeBranch].restoreStack(config.activeBranchStack);
    if (config.activeBranch != _activeBranch) {
      _activeBranch = config.activeBranch;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final branch in _branches) {
      branch.removeListener(notifyListeners);
    }
    // Note: we do NOT dispose the branches themselves. They were
    // supplied externally; their lifecycle is the caller's
    // responsibility (typically tied to the widget that creates them).
    super.dispose();
  }
}

/// One branch of a [GateBranchedShell], typed to its specific
/// route subtype.
///
/// Renders a typed [GateInnerNavigator] wrapped in a `RouterScope<R>`
/// so screens inside the branch can call `context.router<R>()` to get
/// the branch's typed router.
///
/// ```dart
/// GateBranch<HomeRoute>(
///   router: homeRouter,
///   pageBuilder: (context, route) => switch (route) {
///     HomeRoot() => const HomeScreen(),
///     ProductDetail(:final id) => ProductDetailScreen(id: id),
///   },
/// )
/// ```
///
/// The `pageBuilder` is exhaustive over the branch's `R`; you cannot
/// build screens for routes that don't belong to this branch.
class GateBranch<R extends GateRoute> extends StatefulWidget {
  /// Create a branch view bound to [router] with a simple per-route
  /// [pageBuilder].
  const GateBranch({
    super.key,
    required this.router,
    required GatePageBuilder<R> pageBuilder,
    this.pageWrapper,
    this.scope,
  })  : _pageBuilder = pageBuilder,
        _adaptivePageBuilder = null;

  /// Create a branch view bound to [router] with an adaptive
  /// [pageBuilder]. The builder receives a [GateStackContext] for
  /// each entry so it can return [GateAbsorbingPage] to collapse
  /// the master into the detail at wide breakpoints.
  ///
  /// New in v0.9.
  const GateBranch.adaptive({
    super.key,
    required this.router,
    required GateAdaptivePageBuilder<R> pageBuilder,
    this.pageWrapper,
    this.scope,
  })  : _pageBuilder = null,
        _adaptivePageBuilder = pageBuilder;

  /// The typed router driving this branch's stack.
  final GateRouter<R> router;

  final GatePageBuilder<R>? _pageBuilder;
  final GateAdaptivePageBuilder<R>? _adaptivePageBuilder;

  /// Optional override of how each route is wrapped as a [Page].
  /// Defaults to [MaterialPage].
  final GatePageWrapper<R>? pageWrapper;

  /// Optional wrapper for the branch's content. Wrap with
  /// `BlocProvider` / `ProviderScope` / signals containers, etc.
  /// Called once per branch when the shell is built, so branch-scoped
  /// state lives as long as the branch is mounted.
  final Widget Function(BuildContext context, Widget child)? scope;

  @override
  State<GateBranch<R>> createState() => _GateBranchState<R>();
}

class _GateBranchState<R extends GateRoute> extends State<GateBranch<R>> {
  late final GlobalKey<NavigatorState> _navKey =
      GlobalKey<NavigatorState>(debugLabel: 'gate-branch-$R');

  @override
  Widget build(BuildContext context) {
    Widget content = GateInnerNavigator<R>(
      router: widget.router,
      navigatorKey: _navKey,
      pageBuilder: widget._pageBuilder,
      adaptivePageBuilder: widget._adaptivePageBuilder,
      pageWrapper: widget.pageWrapper,
    );
    final scope = widget.scope;
    if (scope != null) {
      content = scope(context, content);
    }
    // RouterScope<R> with the branch's specific subtype, so
    // context.router<R>() inside a branch screen resolves to this
    // branch's typed router. context.router<AppRoute>() bypasses this
    // scope (different exact type) and finds the main app's scope
    // above.
    return RouterScope<R>(router: widget.router, child: content);
  }
}

/// Signature for the chrome around a [GateBranchedShell] — typically a
/// [Scaffold] with a bottom nav bar.
typedef GateBranchedShellChromeBuilder = Widget Function(
  BuildContext context,
  int activeBranch,
  Widget branchContent,
  void Function(int branch) switchBranch,
);

/// A bottom-nav shell whose branches have **different** route types.
///
/// Pass a [BranchedShellRouter] and a parallel list of [GateBranch]
/// widgets (one per branch, each typed to its own `R`). The shell
/// handles back-button routing: in-branch back pops the branch; at
/// branch root, back falls through to the parent router.
///
/// ```dart
/// GateBranchedShell(
///   shell: shell,
///   branches: [
///     GateBranch<HomeRoute>(router: homeRouter, pageBuilder: ...),
///     GateBranch<DiscoverRoute>(router: discoverRouter, pageBuilder: ...),
///     GateBranch<ProfileRoute>(router: profileRouter, pageBuilder: ...),
///   ],
///   chromeBuilder: (context, active, branchContent, switchBranch) {
///     return Scaffold(
///       body: branchContent,
///       bottomNavigationBar: NavigationBar(
///         selectedIndex: active,
///         onDestinationSelected: switchBranch,
///         destinations: const [/* ... */],
///       ),
///     );
///   },
/// )
/// ```
///
/// Inside a branch screen, `context.router<BranchR>()` resolves to that
/// branch's typed router; `context.branchedShell()` resolves to the
/// enclosing [BranchedShellRouter] for `switchTo` etc.
class GateBranchedShell extends StatefulWidget {
  /// Create a branched shell driven by [shell] with one widget per
  /// branch in [branches]. The length of [branches] must equal
  /// `shell.branchCount`.
  const GateBranchedShell({
    super.key,
    required this.shell,
    required this.branches,
    required this.chromeBuilder,
  });

  /// The shell's state aggregator. Held externally so the caller can
  /// drive `switchTo` from elsewhere and listen for changes.
  final BranchedShellRouter shell;

  /// One widget per branch, in the same order as `shell.branches`.
  /// Each entry is typically a [GateBranch] typed to its branch's
  /// route subtype.
  final List<Widget> branches;

  /// Builds the chrome (scaffold, bottom nav, etc.) around the active
  /// branch's content.
  final GateBranchedShellChromeBuilder chromeBuilder;

  @override
  State<GateBranchedShell> createState() => _GateBranchedShellState();
}

class _GateBranchedShellState extends State<GateBranchedShell> {
  @override
  void initState() {
    super.initState();
    assert(
      widget.shell.branchCount == widget.branches.length,
      'GateBranchedShell: shell has ${widget.shell.branchCount} branches '
      'but ${widget.branches.length} branch widgets were provided.',
    );
    widget.shell.addListener(_onChange);
  }

  GateNestedHost? _host;

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = GateNestedHostScope.maybeOf(context);
    if (!identical(host, _host)) {
      _host?.unregisterNested(widget.shell);
      _host = host;
      _host?.registerNested(widget.shell);
    }
  }

  @override
  void didUpdateWidget(GateBranchedShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.shell, widget.shell)) {
      oldWidget.shell.removeListener(_onChange);
      widget.shell.addListener(_onChange);
      _host?.unregisterNested(oldWidget.shell);
      _host?.registerNested(widget.shell);
    }
  }

  @override
  void dispose() {
    _host?.unregisterNested(widget.shell);
    widget.shell.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // canPop = true when the active branch is at root — let the
      // parent router pop the shell itself. canPop = false otherwise
      // — we handle the back by popping within the branch.
      canPop: !widget.shell.currentCanPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (widget.shell.currentCanPop) {
          widget.shell.popCurrent();
        }
      },
      child: BranchedShellScope(
        shell: widget.shell,
        child: Builder(
          builder: (context) {
            final branchContent = IndexedStack(
              index: widget.shell.activeBranch,
              children: widget.branches,
            );
            return widget.chromeBuilder(
              context,
              widget.shell.activeBranch,
              branchContent,
              widget.shell.switchTo,
            );
          },
        ),
      ),
    );
  }
}

/// Inherited widget exposing the [BranchedShellRouter] to descendants.
///
/// Look up via `context.branchedShell()`.
class BranchedShellScope extends InheritedWidget {
  /// Create a scope around [child] exposing [shell].
  const BranchedShellScope({
    super.key,
    required this.shell,
    required super.child,
  });

  /// The shell exposed at this scope.
  final BranchedShellRouter shell;

  /// Look up the nearest [BranchedShellScope]. Throws if none is found.
  static BranchedShellScope of(BuildContext context) {
    final scope = maybeOf(context);
    if (scope == null) {
      throw FlutterError(
        'BranchedShellScope not found in widget tree.\n'
        'Ensure the calling widget is inside a GateBranchedShell.',
      );
    }
    return scope;
  }

  /// Like [of], but returns `null` if no scope is found.
  static BranchedShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BranchedShellScope>();

  @override
  bool updateShouldNotify(BranchedShellScope old) =>
      !identical(old.shell, shell);
}

/// Convenience accessor for the enclosing [BranchedShellRouter].
extension GateBranchedShellContextX on BuildContext {
  /// The enclosing branched shell. Use this to switch tabs
  /// programmatically: `context.branchedShell().switchTo(2)`.
  BranchedShellRouter branchedShell() => BranchedShellScope.of(this).shell;
}
