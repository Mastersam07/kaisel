// Lazy + deferred shell branches (v0.21).
//
// `KaiselBranchedShell.specs(lazy: true)` builds each tab's screen only on first
// visit and keeps it alive afterwards — the Home counter survives tab switches.
// The Reports tab is a `KaiselBranchSpec.deferred`: its screen lives behind a
// `deferred as` import and loads on first visit, showing a placeholder, an
// error + retry on failure (a flaky load is simulated), then the screen.
//
//   flutter run -t lib/main_lazy_shell.dart
//
// Watch the console: each branch's builder logs only when that tab is first
// opened — Discover and Reports never build until you tap them.
import 'package:flutter/material.dart';
import 'package:kaisel/kaisel.dart';

import 'lazy_reports.dart' deferred as reports;

sealed class HomeRoute extends KaiselRoute {
  const HomeRoute();
}

final class HomeRoot extends HomeRoute {
  const HomeRoot();
}

sealed class DiscoverRoute extends KaiselRoute {
  const DiscoverRoute();
}

final class DiscoverRoot extends DiscoverRoute {
  const DiscoverRoot();
}

sealed class ReportsRoute extends KaiselRoute {
  const ReportsRoute();
}

final class ReportsRoot extends ReportsRoute {
  const ReportsRoot();
}

// The main stack hosts the shell as a single route, wired through
// KaiselRouterConfig like the other examples.
sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

final class ShellHost extends AppRoute {
  const ShellHost();
}

final _config = KaiselRouterConfig<AppRoute>(
  initial: const ShellHost(),
  builder: (context, route) => switch (route) {
    ShellHost() => const _LazyShell(),
  },
);

void main() => runApp(MaterialApp.router(routerConfig: _config));

// Simulate a flaky deferred load: ~1s delay, fails the first time so the error +
// retry path is visible, then succeeds. A real app passes `reports.loadLibrary`
// directly.
int _reportsAttempts = 0;
Future<void> _loadReports() async {
  _reportsAttempts++;
  await Future<void>.delayed(const Duration(seconds: 1));
  if (_reportsAttempts == 1) {
    throw Exception('Simulated flaky network');
  }
  await reports.loadLibrary();
}

class _LazyShell extends StatelessWidget {
  const _LazyShell();

  @override
  Widget build(BuildContext context) {
    return KaiselBranchedShell.specs(
      lazy: true,
      branches: [
        KaiselBranchSpec<HomeRoute>(
          initial: const HomeRoot(),
          builder: (context, route) {
            debugPrint('built Home');
            return const _HomeScreen();
          },
        ),
        KaiselBranchSpec<DiscoverRoute>(
          initial: const DiscoverRoot(),
          builder: (context, route) {
            debugPrint('built Discover');
            return const Center(child: Text('Discover'));
          },
        ),
        KaiselBranchSpec<ReportsRoute>.deferred(
          initial: const ReportsRoot(),
          loadLibrary: _loadReports,
          placeholder: const _Loading(),
          errorBuilder: (context, error, retry) =>
              _LoadError(error: error, onRetry: retry),
          builder: (context, route) {
            debugPrint('built Reports');
            return reports.ReportsScreen();
          },
        ),
      ],
      chromeBuilder: (context, active, content, switchBranch) => Scaffold(
        appBar: AppBar(title: const Text('Lazy + deferred shell')),
        body: content,
        bottomNavigationBar: NavigationBar(
          selectedIndex: active,
          onDestinationSelected: switchBranch,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.explore), label: 'Discover'),
            NavigationDestination(
              icon: Icon(Icons.bar_chart),
              label: 'Reports',
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeScreen extends StatefulWidget {
  const _HomeScreen();

  @override
  State<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<_HomeScreen> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Switch tabs and come back — the count survives, because '
            'a built branch is kept alive.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text('$_count', style: Theme.of(context).textTheme.headlineMedium),
          FilledButton(
            onPressed: () => setState(() => _count++),
            child: const Text('+1'),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 12),
        Text('Loading Reports…'),
      ],
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 44),
        const SizedBox(height: 8),
        Text("Couldn't load Reports.\n$error", textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
