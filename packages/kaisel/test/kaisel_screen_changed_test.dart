import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

sealed class _App extends KaiselRoute {
  const _App();
}

final class _MainShell extends _App {
  const _MainShell();
}

final class _Settings extends _App {
  const _Settings();
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

void main() {
  late List<String> screens;
  late BranchedShellRouter shell;

  KaiselRouterConfig<_App> configFor() => KaiselRouterConfig<_App>(
    initial: const _MainShell(),
    onScreenChanged: (route) => screens.add(route.routeName),
    builder: (context, route) => switch (route) {
      _Settings() => const Scaffold(body: Text('settings')),
      _MainShell() => KaiselBranchedShell.specs(
        branches: [
          KaiselBranchSpec<_HomeRoute>(
            initial: const _HomeRoot(),
            builder: (context, r) => Scaffold(body: Text('home $r')),
          ),
          KaiselBranchSpec<_OtherRoute>(
            initial: const _OtherRoot(),
            builder: (context, r) => Scaffold(body: Text('other $r')),
          ),
        ],
        chromeBuilder: (context, active, content, switchBranch) {
          shell = context.shell() as BranchedShellRouter;
          return content;
        },
      ),
    },
  );

  setUp(() => screens = <String>[]);

  testWidgets('reports the branch screen, not the route hosting the shell', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: configFor()));
    await tester.pumpAndSettle();

    expect(screens, ['_HomeRoot']);
  });

  testWidgets('tab A -> B -> A reports each screen once, in order', (
    tester,
  ) async {
    final config = configFor();
    await tester.pumpWidget(MaterialApp.router(routerConfig: config));
    await tester.pumpAndSettle();

    shell.switchTo(1);
    await tester.pumpAndSettle();
    shell.switchTo(0);
    await tester.pumpAndSettle();

    expect(screens, ['_HomeRoot', '_OtherRoot', '_HomeRoot']);
  });

  testWidgets('follows navigation inside a branch and on the main stack', (
    tester,
  ) async {
    final config = configFor();
    await tester.pumpWidget(MaterialApp.router(routerConfig: config));
    await tester.pumpAndSettle();

    await shell.current.restoreStack(const [_HomeRoot(), _HomeDetail()]);
    await tester.pumpAndSettle();
    await config.router.push(const _Settings());
    await tester.pumpAndSettle();
    await config.router.pop();
    await tester.pumpAndSettle();

    expect(screens, ['_HomeRoot', '_HomeDetail', '_Settings', '_MainShell']);
  });

  testWidgets('ignores dialogs and other imperative overlays', (tester) async {
    final config = configFor();
    await tester.pumpWidget(MaterialApp.router(routerConfig: config));
    await tester.pumpAndSettle();
    final before = [...screens];

    final context = tester.element(find.byType(Scaffold).first);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('dialog')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('dialog'), findsOneWidget);
    expect(screens, before);
  });
}
