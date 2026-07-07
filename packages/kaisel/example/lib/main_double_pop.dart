// A plain main-stack push does NOT reproduce this, because predictive back is
// wired for the ROOT navigator; the shell puts the detail on a nested navigator,
// which is the gap.
//
// Predictive back must be on: android/app/src/main/AndroidManifest.xml has
//   android:enableOnBackInvokedCallback="true"  (already added; on by default on
//   Android 15+).

import 'package:flutter/material.dart';
import 'package:kaisel/kaisel.dart';

sealed class _App extends KaiselRoute {
  const _App();
}

final class _MainShell extends _App {
  const _MainShell();
}

sealed class _HomeRoute extends KaiselRoute {
  const _HomeRoute();
}

final class _HomeRoot extends _HomeRoute {
  const _HomeRoot();
}

final class _HomeDetail extends _HomeRoute {
  const _HomeDetail(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}

sealed class _OtherRoute extends KaiselRoute {
  const _OtherRoute();
}

final class _OtherRoot extends _OtherRoute {
  const _OtherRoot();
}

final _config = KaiselRouterConfig<_App>(
  initial: const _MainShell(),
  builder: (context, route) => switch (route) {
    _MainShell() => KaiselBranchedShell.specs(
      branches: [
        KaiselBranchSpec<_HomeRoute>(
          initial: const _HomeRoot(),
          builder: (context, r) => switch (r) {
            _HomeRoot() => Scaffold(
              appBar: AppBar(
                title: const Text('Home'),
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
              ),
              backgroundColor: const Color(0xFF1565C0),
              body: ListView(
                children: [
                  for (final id in ['1', '2', '3'])
                    ListTile(
                      title: Text(
                        'Item $id',
                        style: const TextStyle(color: Colors.white),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Colors.white70,
                      ),
                      onTap: () => context.push(_HomeDetail(id)),
                    ),
                ],
              ),
            ),
            _HomeDetail(:final id) => Scaffold(
              appBar: AppBar(
                title: Text('Detail $id'),
                backgroundColor: const Color(0xFFEF6C00),
                foregroundColor: Colors.white,
              ),
              backgroundColor: const Color(0xFFEF6C00),
              body: const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Press the ANDROID device back button.\n\n'
                    'Watch for a double animation.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 20),
                  ),
                ),
              ),
            ),
          },
        ),
        KaiselBranchSpec<_OtherRoute>(
          initial: const _OtherRoot(),
          builder: (context, r) => Scaffold(
            appBar: AppBar(title: const Text('Other')),
            body: const Center(child: Text('Other tab')),
          ),
        ),
      ],
      chromeBuilder: (context, active, branchContent, switchBranch) => Scaffold(
        body: branchContent,
        bottomNavigationBar: NavigationBar(
          selectedIndex: active,
          onDestinationSelected: switchBranch,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.explore), label: 'Other'),
          ],
        ),
      ),
    ),
  },
);

void main() => runApp(
  MaterialApp.router(routerConfig: _config, debugShowCheckedModeBanner: false),
);
