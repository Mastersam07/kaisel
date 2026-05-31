// Adaptive layout inside a shell branch.
//
// Run from the `example/` directory:
//
//   flutter run -t lib/main_shell_adaptive.dart
//
// What this shows
// ---------------
// `GateBranch.adaptive` (v0.9) lets a single tab inside a
// `GateBranchedShell` use the master-detail absorbing pipeline.
// The shell stays at the bottom at all widths; only the adaptive
// tab's content flips between stacked and side-by-side.
//
// The demo has two branches:
//
// 1. **Films** uses `GateBranch.adaptive` with a master-detail
//    builder. At narrow widths the detail page slides over the
//    list. At wide widths (>= 700px logical) the detail absorbs
//    the list into a single page rendered side-by-side.
//
// 2. **Settings** uses a regular `GateBranch`. Same layout at all
//    widths.
//
// Resize the window past ~700px width to see the Films tab's
// layout flip. The shell's bottom nav bar is unaffected.

import 'package:flutter/material.dart';
import 'package:gate/gate.dart';

const _wideBreakpoint = 700.0;

// Data

class Film {
  const Film({
    required this.id,
    required this.title,
    required this.year,
    required this.director,
    required this.blurb,
  });
  final String id;
  final String title;
  final int year;
  final String director;
  final String blurb;
}

const _films = <Film>[
  Film(
    id: '1',
    title: 'Stalker',
    year: 1979,
    director: 'Andrei Tarkovsky',
    blurb:
        'Three men venture into the Zone, a forbidden territory where '
        'a Room is said to grant the visitor\'s innermost desire.',
  ),
  Film(
    id: '2',
    title: 'The Mirror',
    year: 1975,
    director: 'Andrei Tarkovsky',
    blurb:
        'A dying poet recalls his life in non-linear fragments, '
        'interleaving childhood, wartime, and broken relationships.',
  ),
  Film(
    id: '3',
    title: 'In the Mood for Love',
    year: 2000,
    director: 'Wong Kar-wai',
    blurb:
        'Two neighbors in 1960s Hong Kong discover their spouses are '
        'having an affair, and form a quiet bond of their own.',
  ),
  Film(
    id: '4',
    title: 'Chungking Express',
    year: 1994,
    director: 'Wong Kar-wai',
    blurb:
        'Two lovesick Hong Kong policemen drift through parallel '
        'stories of late-night noodle shops and missed connections.',
  ),
  Film(
    id: '5',
    title: 'Burning',
    year: 2018,
    director: 'Lee Chang-dong',
    blurb:
        'An aimless young writer becomes entangled with a former '
        'classmate and the mysterious wealthy man she\'s seeing.',
  ),
];

Film _filmById(String id) => _films.firstWhere((f) => f.id == id);

// Routes

/// Main router never leaves this route; the shell is the host.
sealed class AppRoute extends GateRoute {
  const AppRoute();
}

final class ShellHost extends AppRoute {
  const ShellHost();
}

/// Films branch routes.
sealed class FilmsRoute extends GateRoute {
  const FilmsRoute();
}

final class FilmsList extends FilmsRoute {
  const FilmsList();
}

final class FilmDetail extends FilmsRoute {
  const FilmDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

/// Settings branch routes.
sealed class SettingsRoute extends GateRoute {
  const SettingsRoute();
}

final class SettingsHome extends SettingsRoute {
  const SettingsHome();
}

// Films screens

class _FilmsListScreen extends StatelessWidget {
  const _FilmsListScreen({this.selectedId});

  /// When rendering as the master pane inside an absorbed page, the
  /// adaptive builder passes the currently selected detail id so the
  /// list can highlight it. When rendering standalone (no absorbed
  /// detail), this stays null.
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Films')),
      body: ListView.separated(
        itemCount: _films.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final film = _films[i];
          final selected = film.id == selectedId;
          return ListTile(
            selected: selected,
            selectedTileColor: const Color(0xFF00D4FF).withOpacity(0.08),
            title: Text(film.title),
            subtitle: Text('${film.director} · ${film.year}'),
            trailing: selected
                ? const Icon(Icons.chevron_right, color: Color(0xFF00D4FF))
                : const Icon(Icons.chevron_right),
            onTap: () {
              // pushOrReplaceTop (v0.11) is the right call for
              // adaptive master-detail: push the detail when the
              // current top is the list, replace when a detail is
              // already on top. See main_adaptive.dart for details.
              context.router<FilmsRoute>().pushOrReplaceTop(
                FilmDetail(film.id),
              );
            },
          );
        },
      ),
    );
  }
}

class _FilmDetailScreen extends StatelessWidget {
  const _FilmDetailScreen({required this.id, this.showBack = true});
  final String id;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final film = _filmById(id);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: showBack,
        title: Text(film.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(film.title, style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 4),
            Text(
              '${film.director} · ${film.year}',
              style: const TextStyle(color: Color(0xFF00D4FF)),
            ),
            const SizedBox(height: 16),
            Text(film.blurb, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

// Settings screen

class _SettingsHomeScreen extends StatelessWidget {
  const _SettingsHomeScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.tune),
            title: Text('Preferences'),
            subtitle: Text('Placeholder'),
          ),
          ListTile(
            leading: Icon(Icons.notifications_outlined),
            title: Text('Notifications'),
            subtitle: Text('Placeholder'),
          ),
          ListTile(
            leading: Icon(Icons.security_outlined),
            title: Text('Privacy'),
            subtitle: Text('Placeholder'),
          ),
          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('About'),
            subtitle: Text('gate example app'),
          ),
        ],
      ),
    );
  }
}

// Adaptive builder for the Films branch

GatePageResult _filmsAdaptiveBuilder(
  BuildContext context,
  FilmsRoute route,
  GateStackContext<FilmsRoute> ctx,
) {
  final isWide = MediaQuery.of(context).size.width >= _wideBreakpoint;

  return switch ((ctx.previous, route, isWide)) {
    // FilmsList absorbs nothing; it always renders standalone.
    (_, FilmsList(), _) => const GateStandalonePage(_FilmsListScreen()),

    // FilmDetail on top of FilmsList at wide widths: collapse the
    // two router entries into one rendered page laid out as
    // master-detail. The list highlights the selected film.
    (FilmsList(), FilmDetail(:final id), true) => GateAbsorbingPage(
      widget: GateMasterDetailScaffold(
        master: _FilmsListScreen(selectedId: id),
        detail: _FilmDetailScreen(id: id, showBack: false),
      ),
      absorbing: 1,
    ),

    // FilmDetail at narrow widths, or stacked on something other
    // than FilmsList: standalone, with the normal back button.
    (_, FilmDetail(:final id), _) => GateStandalonePage(
      _FilmDetailScreen(id: id),
    ),
  };
}

// Shell host

class _ShellHost extends StatefulWidget {
  const _ShellHost();
  @override
  State<_ShellHost> createState() => _ShellHostState();
}

class _ShellHostState extends State<_ShellHost> {
  late final GateRouter<FilmsRoute> _filmsRouter = GateRouter<FilmsRoute>(
    initial: const FilmsList(),
  );
  late final GateRouter<SettingsRoute> _settingsRouter =
      GateRouter<SettingsRoute>(initial: const SettingsHome());
  late final BranchedShellRouter _shell = BranchedShellRouter(
    branches: [_filmsRouter, _settingsRouter],
  );

  @override
  void dispose() {
    _shell.dispose();
    _filmsRouter.dispose();
    _settingsRouter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GateBranchedShell(
      shell: _shell,
      branches: [
        // Films tab uses the adaptive constructor so its branch
        // navigator runs through buildAdaptivePages and the
        // master-detail absorb works inside the tab.
        GateBranch<FilmsRoute>.adaptive(
          router: _filmsRouter,
          pageBuilder: _filmsAdaptiveBuilder,
        ),
        // Settings tab uses the regular constructor: same layout
        // at all widths.
        GateBranch<SettingsRoute>(
          router: _settingsRouter,
          pageBuilder: (context, route) => switch (route) {
            SettingsHome() => const _SettingsHomeScreen(),
          },
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
                icon: Icon(Icons.local_movies_outlined),
                selectedIcon: Icon(Icons.local_movies),
                label: 'Films',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}

// App

class ShellAdaptiveApp extends StatefulWidget {
  const ShellAdaptiveApp({super.key});
  @override
  State<ShellAdaptiveApp> createState() => _ShellAdaptiveAppState();
}

class _ShellAdaptiveAppState extends State<ShellAdaptiveApp> {
  late final GateRouter<AppRoute> _router;
  late final GateRouterDelegate<AppRoute> _delegate;

  @override
  void initState() {
    super.initState();
    _router = GateRouter<AppRoute>(initial: const ShellHost());
    _delegate = GateRouterDelegate<AppRoute>(
      router: _router,
      builder: (context, route) => switch (route) {
        ShellHost() => const _ShellHost(),
      },
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
      title: 'gate shell-adaptive demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00D4FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        cardColor: const Color(0xFF14141C),
        useMaterial3: true,
      ),
      routerDelegate: _delegate,
      routeInformationParser: _NoopParser(_router),
    );
  }
}

class _NoopParser extends RouteInformationParser<GateConfig<AppRoute>> {
  _NoopParser(this.router);
  final GateRouter<AppRoute> router;
  @override
  Future<GateConfig<AppRoute>> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    return GateConfig<AppRoute>(mainStack: router.stack);
  }
}

void main() {
  runApp(const ShellAdaptiveApp());
}
