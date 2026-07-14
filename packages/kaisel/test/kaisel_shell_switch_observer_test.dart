import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// A tab switch changes the visible screen without any Navigator route event
// (only the branch container's index changes), so the shells report it to the
// app's `observers:` as a didReplace of the visible tops. In-branch navigation
// must not double-report: the branch navigator's own real events cover it.

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
  const _HomeDetail();
}

sealed class _OtherRoute extends KaiselRoute {
  const _OtherRoute();
}

final class _OtherRoot extends _OtherRoute {
  const _OtherRoot();
}

class _Recorder extends NavigatorObserver {
  _Recorder(this.replaces);

  final List<(Object?, Object?)> replaces; // (old arguments, new arguments)

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replaces.add((oldRoute?.settings.arguments, newRoute?.settings.arguments));
  }
}

void main() {
  testWidgets('branched shell: tab switches report the visible-screen change', (
    tester,
  ) async {
    final replaces = <(Object?, Object?)>[];
    late BranchedShellRouter shellRef;
    final config = KaiselRouterConfig<_App>(
      initial: const _MainShell(),
      observers: () => [_Recorder(replaces)],
      builder: (context, route) => KaiselBranchedShell.specs(
        branches: [
          KaiselBranchSpec<_HomeRoute>(
            initial: const _HomeRoot(),
            builder: (context, r) => Text('home $r'),
          ),
          KaiselBranchSpec<_OtherRoute>(
            initial: const _OtherRoot(),
            builder: (context, r) => Text('other $r'),
          ),
        ],
        chromeBuilder: (context, active, content, switchBranch) {
          shellRef = context.shell() as BranchedShellRouter;
          return content;
        },
      ),
    );
    addTearDown(config.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: config));
    await tester.pumpAndSettle();

    shellRef.switchTo(1);
    await tester.pumpAndSettle();
    expect(replaces, [(const _HomeRoot(), const _OtherRoot())]);

    // In-branch navigation reports nothing synthetic (real events cover it).
    replaces.clear();
    await shellRef.branchAt(0).restoreStack(const [_HomeRoot(), _HomeDetail()]);
    await tester.pumpAndSettle();
    expect(replaces, isEmpty);

    // Switching back reports the *current* top of the target branch.
    shellRef.switchTo(0);
    await tester.pumpAndSettle();
    expect(replaces, [(const _OtherRoot(), const _HomeDetail())]);
  });

  testWidgets('homogeneous shell: tab switch reports', (tester) async {
    final replaces = <(Object?, Object?)>[];
    late void Function(int) switchTab;
    final config = KaiselRouterConfig<_App>(
      initial: const _MainShell(),
      observers: () => [_Recorder(replaces)],
      builder: (context, route) => KaiselShell<_HomeRoute>(
        branchInitials: const [_HomeRoot(), _HomeDetail()],
        pageBuilder: (context, r) => Text('$r'),
        chromeBuilder: (context, active, content, switchBranch) {
          switchTab = switchBranch;
          return content;
        },
      ),
    );
    addTearDown(config.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: config));
    await tester.pumpAndSettle();

    switchTab(1);
    await tester.pumpAndSettle();
    expect(replaces, [(const _HomeRoot(), const _HomeDetail())]);
  });
}
