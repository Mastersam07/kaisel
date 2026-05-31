// Regression test for the initial-mount crash:
//
// Putting a BranchedShell-hosting route as the main router's
// initial route used to crash with "setState called during build"
// because GateBranchedShell.didChangeDependencies fires during the
// initial mount, calls delegate.registerNested, which calls
// _safeNotifyListeners, which used to notify synchronously when
// not in a frame. The initial widget attach happens via Timer.run
// outside any frame, so the SchedulerBinding phase is `idle` even
// though the BuildOwner is mid-build.
//
// Fix (v0.12): _safeNotifyListeners always defers via
// scheduleMicrotask. The test below verifies that pumping an app
// whose initial route hosts a BranchedShell does not throw.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gate/gate.dart';

// Main router has one route, always the shell host.
sealed class _AppRoute extends GateRoute {
  const _AppRoute();
}

final class _ShellHost extends _AppRoute {
  const _ShellHost();
}

// Two branch route types.
sealed class _AlphaRoute extends GateRoute {
  const _AlphaRoute();
}

final class _AlphaHome extends _AlphaRoute {
  const _AlphaHome();
}

sealed class _BetaRoute extends GateRoute {
  const _BetaRoute();
}

final class _BetaHome extends _BetaRoute {
  const _BetaHome();
}

class _Parser extends RouteInformationParser<GateConfig<_AppRoute>> {
  _Parser(this.router);
  final GateRouter<_AppRoute> router;
  @override
  Future<GateConfig<_AppRoute>> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    return GateConfig<_AppRoute>(mainStack: router.stack);
  }
}

class _ShellHostWidget extends StatefulWidget {
  const _ShellHostWidget();
  @override
  State<_ShellHostWidget> createState() => _ShellHostWidgetState();
}

class _ShellHostWidgetState extends State<_ShellHostWidget> {
  late final GateRouter<_AlphaRoute> _alpha =
      GateRouter<_AlphaRoute>(initial: const _AlphaHome());
  late final GateRouter<_BetaRoute> _beta =
      GateRouter<_BetaRoute>(initial: const _BetaHome());
  late final BranchedShellRouter _shell =
      BranchedShellRouter(branches: [_alpha, _beta]);

  @override
  void dispose() {
    _shell.dispose();
    _alpha.dispose();
    _beta.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GateBranchedShell(
      shell: _shell,
      branches: [
        GateBranch<_AlphaRoute>(
          router: _alpha,
          pageBuilder: (context, route) => const Scaffold(body: Text('alpha')),
        ),
        GateBranch<_BetaRoute>(
          router: _beta,
          pageBuilder: (context, route) => const Scaffold(body: Text('beta')),
        ),
      ],
      chromeBuilder: (context, active, branchContent, switchBranch) {
        return Scaffold(
          body: branchContent,
          bottomNavigationBar: NavigationBar(
            selectedIndex: active,
            onDestinationSelected: switchBranch,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Alpha'),
              NavigationDestination(
                icon: Icon(Icons.settings),
                label: 'Beta',
              ),
            ],
          ),
        );
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shell-as-initial-route mounts without setState-during-build',
      (tester) async {
    final mainRouter = GateRouter<_AppRoute>(initial: const _ShellHost());
    final delegate = GateRouterDelegate<_AppRoute>(
      router: mainRouter,
      builder: (context, route) => switch (route) {
        _ShellHost() => const _ShellHostWidget(),
      },
    );
    addTearDown(delegate.dispose);
    addTearDown(mainRouter.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        routerDelegate: delegate,
        routeInformationParser: _Parser(mainRouter),
      ),
    );
    await tester.pumpAndSettle();

    // If the bug were present, pumpWidget would have thrown
    // "setState called during build". Reaching here means the
    // shell mounted cleanly.
    expect(find.text('alpha'), findsOneWidget);

    // And tab switching still works after the deferred microtask.
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(find.text('beta'), findsOneWidget);
  });
}
