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
  /// `KaiselRouter<BranchR>` for some sealed `BranchR`. Every branch is
  /// materialised up front — the caller already holds them — and stays mounted.
  BranchedShellRouter({
    required List<KaiselNavigator> branches,
    int initialBranch = 0,
  }) : assert(branches.isNotEmpty, 'A shell must have at least one branch.'),
       assert(
         initialBranch >= 0 && initialBranch < branches.length,
         'initialBranch out of range',
       ),
       _factories = [for (final branch in branches) (() => branch)],
       _branchCount = branches.length,
       _ownsCreated = false,
       _activeBranch = initialBranch {
    for (var i = 0; i < _branchCount; i++) {
      _ensure(i);
    }
  }

  /// Create a shell whose branches are built **lazily** — each
  /// [branchFactories] entry runs the first time its branch becomes active (or
  /// is restored into), not up front. Only [initialBranch] is built on
  /// construction; the rest stay unbuilt until visited, and a built branch is
  /// kept alive afterwards so its state survives tab switches. Because the shell
  /// creates these routers, it also disposes the ones it built.
  ///
  /// This is the controller behind `KaiselBranchedShell.specs(lazy: true)`. The
  /// eager default ([BranchedShellRouter.new]) is unchanged.
  BranchedShellRouter.lazy({
    required List<KaiselNavigator Function()> branchFactories,
    int initialBranch = 0,
  }) : assert(
         branchFactories.isNotEmpty,
         'A shell must have at least one branch.',
       ),
       assert(
         initialBranch >= 0 && initialBranch < branchFactories.length,
         'initialBranch out of range',
       ),
       _factories = branchFactories,
       _branchCount = branchFactories.length,
       _ownsCreated = true,
       _activeBranch = initialBranch {
    _ensure(initialBranch);
  }

  final List<KaiselNavigator Function()> _factories;
  final int _branchCount;
  final Map<int, KaiselNavigator> _created = {};
  final bool _ownsCreated;

  int _activeBranch;

  bool _replacesHistoryEntry = false;

  /// Whether the active branch's most recent committed change should overwrite
  /// the browser history entry rather than add one — so a `replaceTop` / `set`
  /// inside a branch is reported as a replace. A branch switch resets it to
  /// `false` (selecting a tab adds an entry).
  @override
  bool get replacesHistoryEntry => _replacesHistoryEntry;

  final Map<int, VoidCallback> _branchListeners = {};

  KaiselNavigator _ensure(int i) {
    final existing = _created[i];
    if (existing != null) return existing;
    final branch = _factories[i]();
    void listener() => _onBranchChanged(i);
    _branchListeners[i] = listener;
    branch.addListener(listener);
    _created[i] = branch;
    return branch;
  }

  void _onBranchChanged(int i) {
    if (i == _activeBranch) {
      _replacesHistoryEntry = current.replacesHistoryEntry;
    }
    notifyListeners();
  }

  StackTrace? _debugLastSwitchOrigin;
  int _debugLastSwitchSeq = 0;

  /// The call site of the most recent [switchTo], for DevTools. Debug only;
  /// null in release.
  StackTrace? get debugLastSwitchOrigin => _debugLastSwitchOrigin;

  /// A monotonic stamp paired with [debugLastSwitchOrigin]. Debug only.
  int get debugLastSwitchSeq => _debugLastSwitchSeq;

  /// The branches that have been built so far, in ascending branch order. Under
  /// the eager constructor this is every branch; under [BranchedShellRouter.lazy]
  /// it is only those activated or restored into so far. Use your own typed
  /// references for type-safe navigation.
  List<KaiselNavigator> get branches => [
    for (var i = 0; i < _branchCount; i++) ?_created[i],
  ];

  /// Index of the currently selected branch.
  @override
  int get activeBranch => _activeBranch;

  /// The currently selected branch (as the non-generic view), built first if a
  /// lazy shell has not yet.
  @override
  KaiselNavigator get current => _ensure(_activeBranch);

  /// Number of branches.
  @override
  int get branchCount => _branchCount;

  /// The branch router at [index], building it on first access if this is a
  /// lazy shell. The shell widget calls this to materialise a branch's view
  /// when it first becomes active.
  KaiselNavigator branchAt(int index) {
    if (index < 0 || index >= _branchCount) {
      throw RangeError.range(index, 0, _branchCount - 1, 'index');
    }
    return _ensure(index);
  }

  /// The built branch at [index], or null if a lazy shell has not built it yet.
  /// Unlike [branchAt] this never builds a branch — it is for inspection
  /// (DevTools) only, so reading it doesn't defeat laziness.
  KaiselNavigator? builtBranchAt(int index) => _created[index];

  /// Whether `pop` on the active branch would remove a route.
  bool get currentCanPop => current.canPop;

  /// Pop on the active branch. Equivalent to `current.pop()` but
  /// expressed as an instance method for clarity at call sites.
  Future<bool> popCurrent() => current.pop();

  /// Select a different branch. No-op if [branch] is already active. Builds the
  /// target branch on first activation (lazy shells).
  @override
  void switchTo(int branch) {
    if (branch < 0 || branch >= _branchCount) {
      throw RangeError.range(branch, 0, _branchCount - 1, 'branch');
    }
    if (branch == _activeBranch) return;
    _ensure(branch);
    _activeBranch = branch;
    _replacesHistoryEntry = false;
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
    // A restored config is external input: a deep link can name a branch this
    // build doesn't mount. Skip it rather than throw (switchTo still throws).
    if (config.activeBranch < 0 || config.activeBranch >= _branchCount) {
      assert(() {
        debugPrint(
          'kaisel: ignoring restored shell branch ${config.activeBranch} — '
          'this shell mounts $_branchCount '
          'branch${_branchCount == 1 ? '' : 'es'} '
          '(0..${_branchCount - 1}). The deep link or codec targets a '
          'branch that does not exist on this build.',
        );
        return true;
      }());
      return;
    }
    // Build the target branch (restore can target one never visited) and replay
    // its stack; inactive branches keep their own in-memory history.
    await _ensure(config.activeBranch).restoreStack(config.activeBranchStack);
    if (config.activeBranch != _activeBranch) {
      _activeBranch = config.activeBranch;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _branchListeners.forEach(
      (i, listener) => _created[i]?.removeListener(listener),
    );
    // A lazy shell disposes the branches it built; an eager shell leaves its
    // externally-owned branches to the caller.
    if (_ownsCreated) {
      for (final branch in _created.values) {
        if (branch case final KaiselChangeNotifier disposable) {
          disposable.dispose();
        }
      }
    }
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
       _adaptiveBuilder = null,
       _loadLibrary = null,
       _placeholder = null,
       _errorBuilder = null;

  /// A branch with an adaptive [builder] (master-detail absorption).
  const KaiselBranchSpec.adaptive({
    required this.initial,
    required KaiselAdaptivePageBuilder<R> builder,
    this.guards = const [],
    this.pageWrapper,
    this.scope,
  }) : _builder = null,
       _adaptiveBuilder = builder,
       _loadLibrary = null,
       _placeholder = null,
       _errorBuilder = null;

  /// A branch whose code loads on first activation. [loadLibrary] — a deferred
  /// import's `loadLibrary` (e.g. `feature.loadLibrary`) — runs the first time
  /// the branch is shown; until it resolves the branch renders [placeholder],
  /// and if it throws the branch renders [errorBuilder] (or [placeholder] when
  /// none is given). [errorBuilder] is passed a `retry` callback that re-runs
  /// the load — useful for a transient (e.g. network) failure, since the branch
  /// is kept alive and so does not reload on its own. Keep the branch's route
  /// values and [initial] in a non-deferred library and put only the screens the
  /// [builder] returns behind the deferred import, so the router, back handling,
  /// and deep links keep working while the code loads. Use with
  /// `KaiselBranchedShell.specs(lazy: true)`.
  KaiselBranchSpec.deferred({
    required this.initial,
    required KaiselPageBuilder<R> builder,
    required Future<void> Function() loadLibrary,
    Widget placeholder = const SizedBox.shrink(),
    Widget Function(BuildContext context, Object error, VoidCallback retry)?
    errorBuilder,
    this.guards = const [],
    this.pageWrapper,
    this.scope,
  }) : _builder = builder,
       _adaptiveBuilder = null,
       _loadLibrary = loadLibrary,
       _placeholder = placeholder,
       _errorBuilder = errorBuilder;

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
  final Future<void> Function()? _loadLibrary;
  final Widget? _placeholder;
  final Widget Function(BuildContext context, Object error, VoidCallback retry)?
  _errorBuilder;

  /// Whether this branch loads its code on first activation
  /// (see [KaiselBranchSpec.deferred]).
  bool get isDeferred => _loadLibrary != null;

  /// Create this branch's router. Called once by the shell.
  KaiselRouter<R> createRouter() =>
      KaiselRouter<R>(initial: initial, guards: guards);

  /// Build this branch's widget around [router] (the one [createRouter]
  /// returned). Non-generic in [router] so the shell can keep a heterogeneous
  /// list of specs; the cast is sound because the shell pairs each spec with
  /// its own router.
  Widget buildBranch(KaiselNavigator router) {
    final typed = router as KaiselRouter<R>;
    final Widget branch = switch ((_builder, _adaptiveBuilder)) {
      (final builder?, _) => KaiselBranch<R>(
        router: typed,
        pageBuilder: builder,
        pageWrapper: pageWrapper,
        scope: scope,
      ),
      (_, final adaptive?) => KaiselBranch<R>.adaptive(
        router: typed,
        pageBuilder: adaptive,
        pageWrapper: pageWrapper,
        scope: scope,
      ),
      // coverage:ignore-start
      _ => throw StateError('KaiselBranchSpec has no builder.'),
      // coverage:ignore-end
    };
    final loadLibrary = _loadLibrary;
    if (loadLibrary == null) return branch;
    return _DeferredBranch(
      loadLibrary: loadLibrary,
      placeholder: _placeholder ?? const SizedBox.shrink(),
      errorBuilder: _errorBuilder,
      child: branch,
    );
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

/// Signature for a custom container in lazy mode (`KaiselBranchedShell.specs`
/// with `lazy: true`). Unlike [KaiselBranchContentBuilder] no branch widgets are
/// pre-built; instead [buildBranch] materialises branch `index` on demand (its
/// router is created the first time you build it). Build only the branches you
/// want mounted and keep built ones alive yourself — e.g. a lazy [PageView].
typedef KaiselLazyBranchContentBuilder =
    Widget Function(
      BuildContext context,
      int activeBranch,
      int branchCount,
      Widget Function(BuildContext context, int index) buildBranch,
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
       initialBranch = 0,
       lazy = false,
       lazyBranchContentBuilder = null;

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
    this.lazyBranchContentBuilder,
    this.lazy = false,
  }) : assert(
         !lazy || branchContentBuilder == null,
         'lazy: true has no pre-built branch list; pass a '
         'lazyBranchContentBuilder instead of a branchContentBuilder.',
       ),
       assert(
         lazy || lazyBranchContentBuilder == null,
         'lazyBranchContentBuilder applies only to lazy: true; use '
         'branchContentBuilder for the eager shell.',
       ),
       specs = branches,
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

  /// Build branches on first activation instead of all up front, keeping built
  /// ones alive (specs mode). Defaults to `false` — the eager [IndexedStack].
  final bool lazy;

  /// Builds the chrome (scaffold, bottom nav, etc.) around the active
  /// branch's content.
  final KaiselBranchedShellChromeBuilder chromeBuilder;

  /// Optional override for how the branches are laid out. When `null`, the
  /// shell uses an [IndexedStack] (all branches mounted, state preserved). Pass
  /// one to use a [PageView] or any other container — see
  /// [KaiselBranchContentBuilder].
  final KaiselBranchContentBuilder? branchContentBuilder;

  /// Optional custom container for `lazy: true`, where branches are built on
  /// demand — see [KaiselLazyBranchContentBuilder]. When `null`, lazy mode uses
  /// a keep-alive [IndexedStack]. Only valid with `lazy: true`.
  final KaiselLazyBranchContentBuilder? lazyBranchContentBuilder;

  @override
  State<KaiselBranchedShell> createState() => _KaiselBranchedShellState();
}

class _KaiselBranchedShellState extends State<KaiselBranchedShell> {
  late BranchedShellRouter _shell;
  late List<Widget> _branches;

  late final List<KaiselBranchSpec> _lazySpecs;

  // Eager specs mode only: routers this state created and must dispose itself.
  List<KaiselRouter<KaiselRoute>>? _ownedRouters;

  bool _ownsShell = false;
  bool _lazy = false;

  KaiselNestedHost? _host;

  @override
  void initState() {
    super.initState();
    switch ((widget.specs, widget.shell)) {
      case (final specs?, _):
        assert(
          widget.lazy || !specs.any((s) => s.isDeferred),
          'KaiselBranchedShell: deferred branch specs require lazy: true, so '
          'their code is loaded on activation rather than at mount.',
        );
        _ownsShell = true;
        if (widget.lazy) {
          _lazy = true;
          _lazySpecs = specs;
          _shell = BranchedShellRouter.lazy(
            branchFactories: [for (final spec in specs) spec.createRouter],
            initialBranch: widget.initialBranch,
          );
          _branches = const [];
        } else {
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
        }
      case (_, final shell?):
        _shell = shell;
        _branches = widget.branches ?? const [];
      // Unreachable: both constructors set exactly one of specs / shell.
      // coverage:ignore-start
      case _:
        throw StateError(
          'KaiselBranchedShell needs either specs or shell + branches.',
        );
      // coverage:ignore-end
    }
    assert(
      _lazy || _shell.branchCount == _branches.length,
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
    if (_ownsShell) return;
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
    if (_ownsShell) {
      _shell.dispose();
      for (final router
          in _ownedRouters ?? const <KaiselRouter<KaiselRoute>>[]) {
        router.dispose();
      }
    }
    super.dispose();
  }

  Widget _buildLazyBranch(BuildContext context, int index) => _wrapBranchBack(
    index,
    KaiselRestorationScope(
      restorationId: 'kaisel-branch-$index',
      child: _lazySpecs[index].buildBranch(_shell.branchAt(index)),
    ),
  );

  // Drive back off each branch's nested-navigator NavigationNotification — the
  // signal Android predictive back syncs its OS preview against — so a branch
  // pop animates once, not twice. Only the active branch intercepts; the guard
  // keeps other mounted branches' PopScopes from also popping it.
  Widget _wrapBranchBack(int index, Widget branch) =>
      NavigatorPopHandler<Object?>(
        enabled: index == _shell.activeBranch,
        onPopWithResult: (_) {
          if (index == _shell.activeBranch && _shell.currentCanPop) {
            _shell.popCurrent();
          }
        },
        child: branch,
      );

  @override
  Widget build(BuildContext context) {
    return KaiselShellScope(
      controller: _shell,
      child: ShellChromeScope(
        child: Builder(
          builder: (context) {
            final restorableBranches = <Widget>[
              for (var i = 0; i < _branches.length; i++)
                _wrapBranchBack(
                  i,
                  KaiselRestorationScope(
                    restorationId: 'kaisel-branch-$i',
                    child: _branches[i],
                  ),
                ),
            ];
            final branchContent = switch ((
              widget.branchContentBuilder,
              widget.lazyBranchContentBuilder,
              _lazy,
            )) {
              (final build?, _, _) => build(
                context,
                _shell.activeBranch,
                restorableBranches,
                _shell.switchTo,
              ),
              (_, final build?, _) => build(
                context,
                _shell.activeBranch,
                _shell.branchCount,
                _buildLazyBranch,
                _shell.switchTo,
              ),
              (_, _, true) => _LazyKeepAliveStack(
                index: _shell.activeBranch,
                itemCount: _shell.branchCount,
                itemBuilder: _buildLazyBranch,
              ),
              (_, _, false) => IndexedStack(
                index: _shell.activeBranch,
                children: restorableBranches,
              ),
            };
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
}

/// Lays out lazily-built branches: each branch is built the first time it
/// becomes active and then kept mounted (off-stage) so its state survives later
/// tab switches. Branches never visited are inert placeholders — the lazy
/// counterpart to the eager [IndexedStack].
class _LazyKeepAliveStack extends StatefulWidget {
  const _LazyKeepAliveStack({
    required this.index,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int index;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  State<_LazyKeepAliveStack> createState() => _LazyKeepAliveStackState();
}

class _LazyKeepAliveStackState extends State<_LazyKeepAliveStack> {
  final Map<int, Widget> _built = {};

  @override
  void initState() {
    super.initState();
    _materialiseActive();
  }

  @override
  void didUpdateWidget(_LazyKeepAliveStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _materialiseActive();
  }

  void _materialiseActive() => _built.putIfAbsent(
    widget.index,
    () => widget.itemBuilder(context, widget.index),
  );

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.itemCount; i++)
          _built[i] ?? const SizedBox.shrink(),
      ],
    );
  }
}

/// Renders [placeholder] while [loadLibrary] runs, swaps in [child] once it
/// resolves, or shows [errorBuilder] (falling back to [placeholder]) if it
/// throws. Built once per branch on first activation, so the load fires once and
/// the loaded child is kept alive by the lazy container.
class _DeferredBranch extends StatefulWidget {
  const _DeferredBranch({
    required this.loadLibrary,
    required this.placeholder,
    required this.errorBuilder,
    required this.child,
  });

  final Future<void> Function() loadLibrary;
  final Widget placeholder;
  final Widget Function(BuildContext context, Object error, VoidCallback retry)?
  errorBuilder;
  final Widget child;

  @override
  State<_DeferredBranch> createState() => _DeferredBranchState();
}

class _DeferredBranchState extends State<_DeferredBranch> {
  bool _loaded = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      await widget.loadLibrary();
      if (mounted) setState(() => _loaded = true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _retry() {
    setState(() => _error = null);
    _run();
  }

  @override
  Widget build(BuildContext context) {
    if (_error case final error?) {
      return widget.errorBuilder?.call(context, error, _retry) ??
          widget.placeholder;
    }
    return _loaded ? widget.child : widget.placeholder;
  }
}
