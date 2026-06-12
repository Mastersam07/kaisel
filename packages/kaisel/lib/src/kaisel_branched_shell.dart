import 'package:flutter/material.dart';
import 'package:kaisel_core/framework.dart';

import 'kaisel_adaptive.dart';
import 'kaisel_inner_navigator.dart';
import 'kaisel_page_wrapper.dart';
import 'kaisel_router_delegate.dart';
import 'kaisel_scope.dart';

/// Aggregator for a shell whose branches have **different** route types.
///
/// Where [ShellRouter] requires every branch to share a
/// single route type, `BranchedShellRouter` lets you keep one sealed
/// type per branch and have the compiler enforce that you never push
/// a `DiscoverRoute` into the Home tab:
///
/// ```dart
/// sealed class HomeRoute extends KaiselRoute { const HomeRoute(); }
/// sealed class DiscoverRoute extends KaiselRoute { const DiscoverRoute(); }
///
/// final homeRouter = KaiselRouter<HomeRoute>(initial: const HomeRoot());
/// final discoverRouter = KaiselRouter<DiscoverRoute>(initial: const DiscoverRoot());
///
/// final shell = BranchedShellRouter(
///   branches: [homeRouter, discoverRouter],
/// );
/// ```
///
/// The shell holds the routers as [KaiselNavigator] (the non-generic
/// slice of [KaiselRouter]) so the list can be heterogeneous — Dart
/// generics are invariant in [KaiselRouter]'s type parameter, so a typed
/// list is not possible. The shell uses only non-generic operations
/// (can-pop and pop on the active branch for back handling); typed
/// pushes happen on the user's own typed router references, or via
/// `context.router<BranchR>()` inside a branch screen.
class BranchedShellRouter extends ChangeNotifier
    implements KaiselNestedHandle, KaiselShellController {
  /// Create a shell aggregating [branches]. Each entry is typically a
  /// `KaiselRouter<BranchR>` for some sealed `BranchR`.
  BranchedShellRouter({
    required List<KaiselNavigator> branches,
    int initialBranch = 0,
  }) : assert(branches.isNotEmpty, 'A shell must have at least one branch.'),
       assert(
         initialBranch >= 0 && initialBranch < branches.length,
         'initialBranch out of range',
       ),
       _branches = List<KaiselNavigator>.unmodifiable(branches),
       _activeBranch = initialBranch {
    for (final branch in _branches) {
      branch.addListener(notifyListeners);
    }
  }

  final List<KaiselNavigator> _branches;
  int _activeBranch;

  StackTrace? _debugLastSwitchOrigin;
  int _debugLastSwitchSeq = 0;

  /// The call site of the most recent [switchTo], for DevTools. Debug only;
  /// null in release.
  StackTrace? get debugLastSwitchOrigin => _debugLastSwitchOrigin;

  /// A monotonic stamp paired with [debugLastSwitchOrigin]. Debug only.
  int get debugLastSwitchSeq => _debugLastSwitchSeq;

  /// The branches, as a non-generic view. Use your own typed
  /// references to access type-safe navigation methods.
  List<KaiselNavigator> get branches => _branches;

  /// Index of the currently selected branch.
  @override
  int get activeBranch => _activeBranch;

  /// The currently selected branch (as the non-generic view).
  @override
  KaiselNavigator get current => _branches[_activeBranch];

  /// Number of branches.
  @override
  int get branchCount => _branches.length;

  /// Whether `pop` on the active branch would remove a route.
  bool get currentCanPop => current.canPop;

  /// Pop on the active branch. Equivalent to `current.pop()` but
  /// expressed as an instance method for clarity at call sites.
  Future<bool> popCurrent() => current.pop();

  /// Select a different branch. No-op if [branch] is already active.
  @override
  void switchTo(int branch) {
    if (branch < 0 || branch >= _branches.length) {
      throw RangeError.range(branch, 0, _branches.length - 1, 'branch');
    }
    if (branch == _activeBranch) return;
    _activeBranch = branch;
    assert(() {
      _debugLastSwitchOrigin = StackTrace.current;
      _debugLastSwitchSeq = kaiselNextOriginSeq();
      return true;
    }());
    notifyListeners();
  }

  // Capture/restore is the bridge between the shell's runtime state
  // and the URL. captureConfig describes what's currently visible;
  // restoreFromConfig replays a captured snapshot. The host filters
  // by configType before calling, but a defensive `is` check inside
  // restoreFromConfig protects against direct misuse.

  @override
  Type get configType => KaiselShellConfig;

  @override
  KaiselShellConfig captureConfig() {
    return KaiselShellConfig(
      activeBranch: _activeBranch,
      activeBranchStack: current.stack,
    );
  }

  @override
  Future<void> restoreFromConfig(KaiselNestedConfig config) async {
    if (config is! KaiselShellConfig) return;
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

/// One branch of a [KaiselBranchedShell], typed to its specific
/// route subtype.
///
/// Renders a typed [KaiselInnerNavigator] wrapped in a `RouterScope<R>`
/// so screens inside the branch can call `context.router<R>()` to get
/// the branch's typed router.
///
/// ```dart
/// KaiselBranch<HomeRoute>(
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
class KaiselBranch<R extends KaiselRoute> extends StatefulWidget {
  /// Create a branch view bound to [router] with a simple per-route
  /// [pageBuilder].
  const KaiselBranch({
    super.key,
    required this.router,
    required KaiselPageBuilder<R> pageBuilder,
    this.pageWrapper,
    this.scope,
  }) : _pageBuilder = pageBuilder,
       _adaptivePageBuilder = null;

  /// Create a branch view bound to [router] with an adaptive
  /// [pageBuilder]. The builder receives a [KaiselStackContext] for
  /// each entry so it can return [KaiselAbsorbingPage] to collapse
  /// the master into the detail at wide breakpoints.
  const KaiselBranch.adaptive({
    super.key,
    required this.router,
    required KaiselAdaptivePageBuilder<R> pageBuilder,
    this.pageWrapper,
    this.scope,
  }) : _pageBuilder = null,
       _adaptivePageBuilder = pageBuilder;

  /// The typed router driving this branch's stack.
  final KaiselRouter<R> router;

  final KaiselPageBuilder<R>? _pageBuilder;
  final KaiselAdaptivePageBuilder<R>? _adaptivePageBuilder;

  /// Optional override of how each route is wrapped as a [Page].
  /// Defaults to [MaterialPage].
  final KaiselPageWrapper<R>? pageWrapper;

  /// Optional wrapper for the branch's content. Wrap with
  /// `BlocProvider` / `ProviderScope` / signals containers, etc.
  /// Called once per branch when the shell is built, so branch-scoped
  /// state lives as long as the branch is mounted.
  final Widget Function(BuildContext context, Widget child)? scope;

  @override
  State<KaiselBranch<R>> createState() => _KaiselBranchState<R>();
}

class _KaiselBranchState<R extends KaiselRoute> extends State<KaiselBranch<R>> {
  late final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>(
    debugLabel: 'kaisel-branch-$R',
  );

  @override
  Widget build(BuildContext context) {
    Widget content = KaiselInnerNavigator<R>(
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

/// A declarative branch for [KaiselBranchedShell.specs]: the branch's [initial]
/// route and its `builder`, with no [KaiselRouter] or [KaiselBranch] to wire by
/// hand. The shell creates one router per spec, owns it (so each branch's stack
/// survives tab switches), and disposes it.
///
/// Each spec keeps its own route type [R], so a heterogeneous
/// `List<KaiselBranchSpec>` still produces correctly-typed routers and
/// branches.
class KaiselBranchSpec<R extends KaiselRoute> {
  /// A branch with a simple per-route [builder].
  const KaiselBranchSpec({
    required this.initial,
    required KaiselPageBuilder<R> builder,
    this.guards = const [],
    this.pageWrapper,
    this.scope,
  }) : _builder = builder,
       _adaptiveBuilder = null;

  /// A branch with an adaptive [builder] (master-detail absorption).
  const KaiselBranchSpec.adaptive({
    required this.initial,
    required KaiselAdaptivePageBuilder<R> builder,
    this.guards = const [],
    this.pageWrapper,
    this.scope,
  }) : _builder = null,
       _adaptiveBuilder = builder;

  /// The branch's initial route.
  final R initial;

  /// Guards applied to this branch's router.
  final List<KaiselGuard<R>> guards;

  /// Optional per-route [Page] wrapper for this branch.
  final KaiselPageWrapper<R>? pageWrapper;

  /// Optional wrapper for the branch's content (DI containers, etc.).
  final Widget Function(BuildContext context, Widget child)? scope;

  final KaiselPageBuilder<R>? _builder;
  final KaiselAdaptivePageBuilder<R>? _adaptiveBuilder;

  /// Create this branch's router. Called once by the shell.
  KaiselRouter<R> createRouter() =>
      KaiselRouter<R>(initial: initial, guards: guards);

  /// Build this branch's widget around [router] (the one [createRouter]
  /// returned). Non-generic in [router] so the shell can keep a heterogeneous
  /// list of specs; the cast is sound because the shell pairs each spec with
  /// its own router.
  Widget buildBranch(KaiselNavigator router) {
    final typed = router as KaiselRouter<R>;
    switch ((_builder, _adaptiveBuilder)) {
      case (final builder?, _):
        return KaiselBranch<R>(
          router: typed,
          pageBuilder: builder,
          pageWrapper: pageWrapper,
          scope: scope,
        );
      case (_, final adaptive?):
        return KaiselBranch<R>.adaptive(
          router: typed,
          pageBuilder: adaptive,
          pageWrapper: pageWrapper,
          scope: scope,
        );
      // Unreachable: both constructors set exactly one builder.
      // coverage:ignore-start
      case _:
        throw StateError('KaiselBranchSpec has no builder.');
      // coverage:ignore-end
    }
  }
}

/// Signature for the chrome around a [KaiselBranchedShell] — typically a
/// [Scaffold] with a bottom nav bar.
typedef KaiselBranchedShellChromeBuilder =
    Widget Function(
      BuildContext context,
      int activeBranch,
      Widget branchContent,
      void Function(int branch) switchBranch,
    );

/// Signature for overriding how a [KaiselBranchedShell] lays its branches out —
/// given the active branch index, the per-branch widgets (in branch order), and
/// the tab switcher.
///
/// Return whatever container suits your UX: a [PageView] for swipeable tabs, a
/// custom animated switcher, etc. When omitted, the shell uses an [IndexedStack]
/// that keeps every branch mounted so per-branch state survives tab switches —
/// if you replace it, preserving that state becomes your responsibility (e.g. a
/// `PageView` with `AutomaticKeepAliveClientMixin` on its children).
typedef KaiselBranchContentBuilder =
    Widget Function(
      BuildContext context,
      int activeBranch,
      List<Widget> branches,
      void Function(int branch) switchBranch,
    );

/// A bottom-nav shell whose branches have **different** route types.
///
/// Pass a [BranchedShellRouter] and a parallel list of [KaiselBranch]
/// widgets (one per branch, each typed to its own `R`). The shell
/// handles back-button routing: in-branch back pops the branch; at
/// branch root, back falls through to the parent router.
///
/// ```dart
/// KaiselBranchedShell(
///   shell: shell,
///   branches: [
///     KaiselBranch<HomeRoute>(router: homeRouter, pageBuilder: ...),
///     KaiselBranch<DiscoverRoute>(router: discoverRouter, pageBuilder: ...),
///     KaiselBranch<ProfileRoute>(router: profileRouter, pageBuilder: ...),
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
/// branch's typed router; `context.shell()` resolves to the enclosing shell
/// controller for `switchTo`, `activeBranch`, `current`, etc.
class KaiselBranchedShell extends StatefulWidget {
  /// Create a branched shell driven by [shell] with one widget per branch in
  /// [branches]. The length of [branches] must equal `shell.branchCount`. Use
  /// this when you want to hold the branch routers yourself; otherwise prefer
  /// [KaiselBranchedShell.specs], which wires them for you.
  const KaiselBranchedShell({
    super.key,
    required BranchedShellRouter this.shell,
    required List<Widget> this.branches,
    required this.chromeBuilder,
    this.branchContentBuilder,
  }) : specs = null,
       initialBranch = 0;

  /// Create a branched shell from declarative [branches] — one
  /// [KaiselBranchSpec] per branch. The shell creates, owns, and disposes the
  /// per-branch routers for you, so you never construct a [KaiselRouter]; each
  /// branch's stack still survives tab switches. Navigate inside a branch with
  /// `context.push(...)`, and switch tabs with `context.shell()`.
  const KaiselBranchedShell.specs({
    super.key,
    required List<KaiselBranchSpec> branches,
    required this.chromeBuilder,
    this.initialBranch = 0,
    this.branchContentBuilder,
  }) : specs = branches,
       shell = null,
       branches = null;

  /// The externally-held aggregator (explicit mode), or `null` in specs mode.
  final BranchedShellRouter? shell;

  /// One widget per branch (explicit mode), or `null` in specs mode.
  final List<Widget>? branches;

  /// Declarative branches (specs mode), or `null` in explicit mode.
  final List<KaiselBranchSpec>? specs;

  /// The branch shown first (specs mode).
  final int initialBranch;

  /// Builds the chrome (scaffold, bottom nav, etc.) around the active
  /// branch's content.
  final KaiselBranchedShellChromeBuilder chromeBuilder;

  /// Optional override for how the branches are laid out. When `null`, the
  /// shell uses an [IndexedStack] (all branches mounted, state preserved). Pass
  /// one to use a [PageView] or any other container — see
  /// [KaiselBranchContentBuilder].
  final KaiselBranchContentBuilder? branchContentBuilder;

  @override
  State<KaiselBranchedShell> createState() => _KaiselBranchedShellState();
}

class _KaiselBranchedShellState extends State<KaiselBranchedShell> {
  // The effective aggregator and branch widgets. In specs mode these are
  // created and owned here; in explicit mode they mirror the widget's fields.
  late BranchedShellRouter _shell;
  late List<Widget> _branches;

  // Routers this state created (specs mode) and must dispose. Null when the
  // caller owns the shell (explicit mode).
  List<KaiselRouter<KaiselRoute>>? _ownedRouters;

  KaiselNestedHost? _host;

  @override
  void initState() {
    super.initState();
    switch ((widget.specs, widget.shell)) {
      case (final specs?, _):
        final routers = [for (final spec in specs) spec.createRouter()];
        _shell = BranchedShellRouter(
          branches: routers,
          initialBranch: widget.initialBranch,
        );
        _branches = [
          for (var i = 0; i < specs.length; i++)
            specs[i].buildBranch(routers[i]),
        ];
        _ownedRouters = routers;
      case (_, final shell?):
        _shell = shell;
        _branches = widget.branches ?? const [];
        _ownedRouters = null;
      // Unreachable: both constructors set exactly one of specs / shell.
      // coverage:ignore-start
      case _:
        throw StateError(
          'KaiselBranchedShell needs either specs or shell + branches.',
        );
      // coverage:ignore-end
    }
    assert(
      _shell.branchCount == _branches.length,
      'KaiselBranchedShell: shell has ${_shell.branchCount} branches '
      'but ${_branches.length} branch widgets were provided.',
    );
    _shell.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = KaiselNestedHostScope.maybeOf(context);
    if (!identical(host, _host)) {
      _host?.unregisterNested(_shell);
      _host = host;
      _host?.registerNested(_shell);
    }
  }

  @override
  void didUpdateWidget(KaiselBranchedShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Specs mode owns its shell for the State's lifetime; only explicit mode
    // can swap an external shell instance.
    if (_ownedRouters != null) return;
    final newShell = widget.shell;
    if (newShell != null && !identical(oldWidget.shell, newShell)) {
      _shell.removeListener(_onChange);
      _host?.unregisterNested(_shell);
      _shell = newShell;
      _branches = widget.branches ?? const [];
      _shell.addListener(_onChange);
      _host?.registerNested(_shell);
    }
  }

  @override
  void dispose() {
    _host?.unregisterNested(_shell);
    _shell.removeListener(_onChange);
    if (_ownedRouters case final routers?) {
      _shell.dispose();
      for (final router in routers) {
        router.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // canPop = true when the active branch is at root — let the
      // parent router pop the shell itself. canPop = false otherwise
      // — we handle the back by popping within the branch.
      canPop: !_shell.currentCanPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_shell.currentCanPop) {
          _shell.popCurrent();
        }
      },
      child: KaiselShellScope(
        controller: _shell,
        child: ShellChromeScope(
          child: Builder(
            builder: (context) {
              final branchContent =
                  widget.branchContentBuilder?.call(
                    context,
                    _shell.activeBranch,
                    _branches,
                    _shell.switchTo,
                  ) ??
                  IndexedStack(index: _shell.activeBranch, children: _branches);
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
}
