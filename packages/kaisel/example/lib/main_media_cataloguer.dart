// Media Cataloguer — example replicating the desktop flows from the
// reference video, with adaptive master-detail layered on the test
// branch so the desktop layout actually earns its width.
//
// Run from the `example/` directory:
//
//   flutter run -t lib/main_media_cataloguer.dart
//
// What this shows
// ---------------
// Six kaisel features composed in a single app:
//
// 1. **Top-level auth state machine.** The main router's stack
//    contains either `LoginRoute` (full-screen, no shell chrome) or
//    `ShellHost` (sidebar + branched content). Toggling between them
//    is just `router.set([...])`; the auth state is the stack.
//
// 2. **Cross-fade between LoginRoute and ShellHost.** A `pageWrapper`
//    on the main delegate pattern-matches on the route pair and
//    returns a custom Page that fades instead of slides. Login and
//    "logged-in app" feel like different surfaces rather than
//    siblings on a stack.
//
// 3. **Branched shell with per-branch typing.** Three branches —
//    Home, Library, Test — each typed with its own sealed route
//    family. Pushing a `HomeRoute` into the Test branch is a compile
//    error, not a runtime concern.
//
// 4. **Per-branch state preservation.** Each branch's router keeps
//    its own stack. Visiting Home and returning to Test brings back
//    the Test branch exactly as you left it, including any pushed
//    detail routes.
//
// 5. **Nested stack inside a branch.** The Test branch pushes
//    `CollectionView(id)` over `TestHome`, then `VideoPlayerView(...)`
//    over that. The shell chrome's inner back button pops within the
//    branch's stack independent of the outer auth state.
//
// 6. **Adaptive master-detail inside the Test branch.** At content
//    widths >= 700px, `CollectionView` and `VideoPlayerView` absorb
//    into one rendered page laid out side-by-side: the media list on
//    the left, the selected video on the right. Selecting a different
//    video uses `pushOrReplaceTop` so the right pane updates in place
//    rather than stacking three entries deep. At narrow widths the
//    video player slides on top of the list as a normal push. The
//    router's stack model is identical in both cases — only the
//    rendering differs.

import 'package:flutter/material.dart';
import 'package:kaisel/kaisel.dart';

// Top-level routes

sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

final class LoginRoute extends AppRoute {
  const LoginRoute();
}

/// Wraps the entire post-login experience: sidebar + breadcrumb +
/// branched content. The shell's branches and per-branch stacks live
/// inside the widget, not on the main router's stack.
final class ShellHost extends AppRoute {
  const ShellHost();
}

// Per-branch routes

sealed class HomeRoute extends KaiselRoute {
  const HomeRoute();
}

final class HomeView extends HomeRoute {
  const HomeView();
}

sealed class LibraryRoute extends KaiselRoute {
  const LibraryRoute();
}

final class LibraryView extends LibraryRoute {
  const LibraryView();
}

/// Test branch demonstrates a deeper nested stack.
sealed class TestRoute extends KaiselRoute {
  const TestRoute();
}

final class TestHome extends TestRoute {
  const TestHome();
}

final class CollectionView extends TestRoute {
  const CollectionView(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

final class VideoPlayerView extends TestRoute {
  const VideoPlayerView({required this.collectionId, required this.fileName});
  final String collectionId;
  final String fileName;
  @override
  List<Object?> get props => [collectionId, fileName];
}

// A stable demo UUID used so the breadcrumb matches across runs.
const _demoCollectionId = '019e88b7-5075-734b-b454-07e4fa729888';

// Demo media catalog. Mock content so the master-detail layout has
// something to chew on at wide widths.
const _demoMedia = <String>[
  'intro.mp4',
  'lesson_01_routes_as_values.mp4',
  'lesson_02_codec_as_bridge.mp4',
  'lesson_03_adaptive_layouts.mp4',
  'outro.mp4',
];

// Wide breakpoint for the master-detail layout in the test branch.
// At or above this content width, CollectionView + VideoPlayerView
// absorb into one rendered page laid out side-by-side. Below, the
// video player slides on top of the collection list.
const _wideBreakpoint = 700.0;

// Top-level fade transition
//
// Login and the logged-in shell are siblings on the main router's
// stack but they feel like different surfaces. Slide-on-push would
// look wrong here; we want a cross-fade so the auth state change
// reads as a state transition rather than a navigation event.

class _FadePage<T> extends Page<T> {
  const _FadePage({required LocalKey super.key, required this.child});
  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) {
    return PageRouteBuilder<T>(
      settings: this,
      pageBuilder: (_, __, ___) => child,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    );
  }
}

Page<Object?> _appPageWrapper(KaiselPageWrapperContext<AppRoute> ctx) {
  // LoginRoute and ShellHost are full-surface auth states swapped with
  // `router.set(...)`, which collapses the main stack to a single entry — so
  // `ctx.previous` is null and we can't pattern-match on the route pair.
  // Fade whenever one of these surfaces appears so the swap cross-fades
  // instead of sliding. (The very first mount fades the login screen in once.)
  if (ctx.route is LoginRoute || ctx.route is ShellHost) {
    return _FadePage<Object?>(key: ctx.key, child: ctx.child);
  }
  return MaterialPage<Object?>(key: ctx.key, child: ctx.child);
}

// Screens

/// Full-screen login. No shell chrome; this lives at the top-level
/// router and replaces the entire surface.
class _LoginScreen extends StatelessWidget {
  const _LoginScreen();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFA8D5D8),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'LoginView',
              style: TextStyle(color: Colors.black87, fontSize: 18),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                // The auth state is the stack. Replace LoginRoute with
                // ShellHost; the page wrapper cross-fades the swap.
                context.router<AppRoute>().set(const [ShellHost()]);
              },
              child: const Text(
                'Go to Content View',
                style: TextStyle(color: Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: Colors.white,
      child: Center(
        child: Text(
          'Home View',
          style: TextStyle(color: Colors.black87, fontSize: 16),
        ),
      ),
    );
  }
}

class _LibraryScreen extends StatelessWidget {
  const _LibraryScreen();

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: Colors.white,
      child: Center(
        child: Text(
          'Library View',
          style: TextStyle(color: Colors.black87, fontSize: 16),
        ),
      ),
    );
  }
}

class _TestHomeScreen extends StatelessWidget {
  const _TestHomeScreen();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Test Home',
              style: TextStyle(color: Colors.black87, fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                context.router<TestRoute>().push(
                  const CollectionView(_demoCollectionId),
                );
              },
              child: const Text(
                'Open demo collection',
                style: TextStyle(color: Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Collection view doubles as master pane and standalone screen.
/// When rendered as the master pane inside an absorbed page,
/// [selectedFileName] is set and the matching item is highlighted.
/// When rendered standalone (narrow widths, or no detail pushed yet),
/// it's null.
class _CollectionScreen extends StatelessWidget {
  const _CollectionScreen({required this.id, this.selectedFileName});
  final String id;
  final String? selectedFileName;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFB2D4D4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Collection View - id: $id',
              style: const TextStyle(color: Colors.black87, fontSize: 13),
            ),
          ),
          const Divider(height: 1, color: Colors.black26),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: _demoMedia.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Colors.black12),
              itemBuilder: (context, i) {
                final fileName = _demoMedia[i];
                final selected = fileName == selectedFileName;
                return ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: Colors.black.withValues(alpha: 0.06),
                  leading: Icon(
                    Icons.play_circle_outline,
                    color: selected ? const Color(0xFF8E2C3A) : Colors.black54,
                  ),
                  title: Text(
                    fileName,
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  trailing: selected
                      ? const Icon(
                          Icons.chevron_right,
                          color: Color(0xFF8E2C3A),
                        )
                      : const Icon(Icons.chevron_right, color: Colors.black38),
                  onTap: () {
                    // pushOrReplaceTop is the right call inside an
                    // adaptive master-detail: push the detail when
                    // the current top is the list, replace it when a
                    // detail is already on top. Tapping a different
                    // video updates the right pane in place instead
                    // of stacking three entries.
                    context.router<TestRoute>().pushOrReplaceTop(
                      VideoPlayerView(collectionId: id, fileName: fileName),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoPlayerScreen extends StatelessWidget {
  const _VideoPlayerScreen({required this.fileName, this.showBack = true});
  final String fileName;

  /// In the absorbed master-detail layout, the detail pane has no
  /// back arrow — popping happens via the list's selection state, not
  /// a back gesture. Standalone (narrow), the back arrow is shown.
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEFB8BE),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.play_arrow,
                  size: 56,
                  color: Color(0xFF8E2C3A),
                ),
                const SizedBox(height: 8),
                Text(
                  'Video Player View',
                  style: TextStyle(
                    color: const Color(0xFF8E2C3A).withValues(alpha: 0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'fileName: $fileName',
                  style: const TextStyle(color: Colors.black87, fontSize: 13),
                ),
              ],
            ),
          ),
          if (showBack)
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                onPressed: () => context.router<TestRoute>().pop(),
                icon: const Icon(Icons.arrow_back, color: Color(0xFF8E2C3A)),
                tooltip: 'Back to collection',
              ),
            ),
        ],
      ),
    );
  }
}

// Adaptive builder for the Test branch. Decides per page whether to
// render standalone or absorb the route below into a side-by-side
// master-detail. Called once per stack entry by the inner navigator.
KaiselPageResult _testAdaptiveBuilder(
  BuildContext context,
  TestRoute route,
  KaiselStackContext<TestRoute> ctx,
) {
  final isWide = MediaQuery.of(context).size.width >= _wideBreakpoint;

  return switch ((ctx.previous, route, isWide)) {
    // TestHome is always standalone.
    (_, TestHome(), _) => const KaiselStandalonePage(_TestHomeScreen()),

    // VideoPlayerView pushed on top of CollectionView at wide widths
    // → absorb the list into the detail as side-by-side panes. The
    // list pane gets the selected fileName so it can highlight the
    // active row.
    (CollectionView(:final id), VideoPlayerView(:final fileName), true) =>
      KaiselAbsorbingPage(
        widget: _MasterDetailScaffold(
          master: _CollectionScreen(id: id, selectedFileName: fileName),
          detail: _VideoPlayerScreen(fileName: fileName, showBack: false),
        ),
        absorbing: 1,
      ),

    // CollectionView always renders the list. Standalone at narrow,
    // standalone at wide when nothing is selected.
    (_, CollectionView(:final id), _) => KaiselStandalonePage(
      _CollectionScreen(id: id),
    ),

    // VideoPlayerView at narrow widths, or on top of something other
    // than CollectionView: standalone, with the back button shown.
    (_, VideoPlayerView(:final fileName), _) => KaiselStandalonePage(
      _VideoPlayerScreen(fileName: fileName),
    ),
  };
}

/// Side-by-side scaffold used when CollectionView absorbs
/// VideoPlayerView at wide widths. Master gets a fixed proportion,
/// detail takes the rest, with a thin divider between.
class _MasterDetailScaffold extends StatelessWidget {
  const _MasterDetailScaffold({required this.master, required this.detail});
  final Widget master;
  final Widget detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 280, child: master),
        const VerticalDivider(width: 1, color: Colors.black26),
        Expanded(child: detail),
      ],
    );
  }
}

// Shell host
//
// Holds three branches, each with its own typed router. The shell's
// own chrome (sidebar + breadcrumb) is built by the chrome builder.

class _ShellHost extends StatefulWidget {
  const _ShellHost();
  @override
  State<_ShellHost> createState() => _ShellHostState();
}

class _ShellHostState extends State<_ShellHost> {
  late final KaiselRouter<HomeRoute> _homeRouter = KaiselRouter<HomeRoute>(
    initial: const HomeView(),
  );
  late final KaiselRouter<LibraryRoute> _libraryRouter =
      KaiselRouter<LibraryRoute>(initial: const LibraryView());
  late final KaiselRouter<TestRoute> _testRouter = KaiselRouter<TestRoute>(
    initial: const TestHome(),
  );

  late final BranchedShellRouter _shell = BranchedShellRouter(
    branches: [_homeRouter, _libraryRouter, _testRouter],
  );

  @override
  void dispose() {
    _shell.dispose();
    _homeRouter.dispose();
    _libraryRouter.dispose();
    _testRouter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KaiselBranchedShell(
      shell: _shell,
      branches: [
        KaiselBranch<HomeRoute>(
          router: _homeRouter,
          pageBuilder: (context, route) => switch (route) {
            HomeView() => const _HomeScreen(),
          },
        ),
        KaiselBranch<LibraryRoute>(
          router: _libraryRouter,
          pageBuilder: (context, route) => switch (route) {
            LibraryView() => const _LibraryScreen(),
          },
        ),
        KaiselBranch<TestRoute>.adaptive(
          router: _testRouter,
          pageBuilder: _testAdaptiveBuilder,
        ),
      ],
      chromeBuilder: (context, active, branchContent, switchBranch) {
        return _AppChrome(
          activeBranchIndex: active,
          onSwitchBranch: switchBranch,
          homeRouter: _homeRouter,
          libraryRouter: _libraryRouter,
          testRouter: _testRouter,
          branchContent: branchContent,
        );
      },
    );
  }
}

// Chrome (sidebar + breadcrumb + back/forward)

class _AppChrome extends StatelessWidget {
  const _AppChrome({
    required this.activeBranchIndex,
    required this.onSwitchBranch,
    required this.homeRouter,
    required this.libraryRouter,
    required this.testRouter,
    required this.branchContent,
  });

  final int activeBranchIndex;
  final void Function(int) onSwitchBranch;
  final KaiselRouter<HomeRoute> homeRouter;
  final KaiselRouter<LibraryRoute> libraryRouter;
  final KaiselRouter<TestRoute> testRouter;
  final Widget branchContent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2A2A2A),
      child: SafeArea(
        child: Column(
          children: [
            // Outer chrome: app title bar with browser-style back/forward.
            // These are decorative in the demo — they could be wired to a
            // global navigation history if you wanted browser-like behavior
            // across branch switches.
            Container(
              height: 36,
              color: const Color(0xFF1A1A1A),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: const Row(
                children: [
                  Icon(Icons.web_asset, size: 14, color: Colors.white54),
                  SizedBox(width: 12),
                  Text(
                    '[DEV] Media Cataloguer',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
            Container(
              height: 40,
              color: const Color(0xFF5A5A5A),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    iconSize: 18,
                    color: Colors.white54,
                    onPressed: null,
                    icon: const Icon(Icons.arrow_back_ios_new),
                  ),
                  IconButton(
                    iconSize: 18,
                    color: Colors.white54,
                    onPressed: null,
                    icon: const Icon(Icons.arrow_forward_ios),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _InnerNavBar(
                      activeBranchIndex: activeBranchIndex,
                      homeRouter: homeRouter,
                      libraryRouter: libraryRouter,
                      testRouter: testRouter,
                    ),
                  ),
                  IconButton(
                    iconSize: 14,
                    color: Colors.white70,
                    tooltip: 'Sign out',
                    onPressed: () {
                      // Return to login surface. The page wrapper cross-fades.
                      context.router<AppRoute>().set(const [LoginRoute()]);
                    },
                    icon: const Icon(Icons.logout),
                  ),
                ],
              ),
            ),
            // Sidebar + content area
            Expanded(
              child: Row(
                children: [
                  _Sidebar(
                    activeBranchIndex: activeBranchIndex,
                    onSwitchBranch: onSwitchBranch,
                  ),
                  Expanded(child: branchContent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inner back/forward + breadcrumb. Hooks into the active branch's
/// router so the back arrow pops within the current branch only.
class _InnerNavBar extends StatelessWidget {
  const _InnerNavBar({
    required this.activeBranchIndex,
    required this.homeRouter,
    required this.libraryRouter,
    required this.testRouter,
  });

  final int activeBranchIndex;
  final KaiselRouter<HomeRoute> homeRouter;
  final KaiselRouter<LibraryRoute> libraryRouter;
  final KaiselRouter<TestRoute> testRouter;

  @override
  Widget build(BuildContext context) {
    // Pick the active router based on the active branch index. We
    // listen to it so the breadcrumb updates when the branch's stack
    // changes (push, pop, replaceTop).
    final activeRouter = switch (activeBranchIndex) {
      0 => homeRouter,
      1 => libraryRouter,
      _ => testRouter,
    };

    return ListenableBuilder(
      listenable: activeRouter.asListenable(),
      builder: (context, _) {
        final (label, path, canPop) = _describeActive();
        return Row(
          children: [
            IconButton(
              iconSize: 16,
              color: canPop ? Colors.white : Colors.white38,
              onPressed: canPop ? _popActive : null,
              icon: const Icon(Icons.arrow_back_ios_new),
            ),
            IconButton(
              iconSize: 16,
              color: Colors.white38,
              onPressed: null,
              icon: const Icon(Icons.arrow_forward_ios),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    path,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Returns (human-readable label, URL path, whether back is enabled)
  /// based on the active branch and its current stack.
  (String, String, bool) _describeActive() {
    switch (activeBranchIndex) {
      case 0:
        return ('Home', '/home', homeRouter.stack.length > 1);
      case 1:
        return ('Library', '/library', libraryRouter.stack.length > 1);
      default:
        final stack = testRouter.stack;
        final top = stack.last;
        return switch (top) {
          TestHome() => ('Test', '/test', false),
          CollectionView(:final id) => (
            'Collection - $id',
            '/collection/$id',
            true,
          ),
          VideoPlayerView(:final collectionId, :final fileName) => (
            'Collection - $collectionId',
            '/collection/$collectionId/$fileName',
            true,
          ),
        };
    }
  }

  void _popActive() {
    switch (activeBranchIndex) {
      case 0:
        homeRouter.pop();
      case 1:
        libraryRouter.pop();
      default:
        testRouter.pop();
    }
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.activeBranchIndex,
    required this.onSwitchBranch,
  });

  final int activeBranchIndex;
  final void Function(int) onSwitchBranch;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      color: const Color(0xFF7A7A7A),
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          _SidebarItem(
            icon: Icons.home,
            label: 'Home',
            selected: activeBranchIndex == 0,
            onTap: () => onSwitchBranch(0),
          ),
          const SizedBox(height: 24),
          _SidebarItem(
            icon: Icons.account_balance,
            label: 'Library',
            selected: activeBranchIndex == 1,
            onTap: () => onSwitchBranch(1),
          ),
          const SizedBox(height: 24),
          _SidebarItem(
            icon: Icons.folder,
            label: 'test',
            selected: activeBranchIndex == 2,
            onTap: () => onSwitchBranch(2),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? Colors.black : Colors.black87,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : Colors.black87,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// App

class MediaCataloguerApp extends StatefulWidget {
  const MediaCataloguerApp({super.key});
  @override
  State<MediaCataloguerApp> createState() => _MediaCataloguerAppState();
}

class _MediaCataloguerAppState extends State<MediaCataloguerApp> {
  late final KaiselRouter<AppRoute> _router;
  late final KaiselRouterDelegate<AppRoute> _delegate;

  @override
  void initState() {
    super.initState();
    _router = KaiselRouter<AppRoute>(initial: const LoginRoute());
    _delegate = KaiselRouterDelegate<AppRoute>(
      router: _router,
      builder: (context, route) => switch (route) {
        LoginRoute() => const _LoginScreen(),
        ShellHost() => const _ShellHost(),
      },
      pageWrapper: _appPageWrapper,
    );
  }

  @override
  void dispose() {
    _delegate.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '[DEV] Media Cataloguer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00D4FF),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      routerDelegate: _delegate,
      routeInformationParser: _NoopParser(_router),
    );
  }
}

class _NoopParser extends RouteInformationParser<KaiselConfig<AppRoute>> {
  _NoopParser(this.router);
  final KaiselRouter<AppRoute> router;
  @override
  Future<KaiselConfig<AppRoute>> parseRouteInformation(
    RouteInformation routeInformation,
  ) async => KaiselConfig<AppRoute>(mainStack: router.stack);
}

void main() => runApp(const MediaCataloguerApp());
