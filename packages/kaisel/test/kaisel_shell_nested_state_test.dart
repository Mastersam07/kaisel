import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// KaiselShell reports its active branch the way KaiselBranchedShell does, so
// a codec can put it in the URL and the stack survives a restart.

sealed class _R extends KaiselRoute {
  const _R();
}

final class _Home extends _R {
  const _Home();
}

final class _Plain extends _R {
  const _Plain();
}

final class _Tabs extends _R {
  const _Tabs();
}

final class _Group extends _R implements KaiselModalRoute<void> {
  const _Group();
}

sealed class _T extends KaiselRoute {
  const _T();
}

final class _A extends _T {
  const _A();
}

final class _ADeep extends _T {
  const _ADeep();
}

final class _B extends _T {
  const _B();
}

final class _Inner extends _T {
  const _Inner();
}

const _names = <String, _T>{
  'A': _A(),
  'ADeep': _ADeep(),
  'B': _B(),
  'Inner': _Inner(),
};

String _name(KaiselRoute route) => switch (route) {
  _A() => 'A',
  _ADeep() => 'ADeep',
  _B() => 'B',
  _Inner() => 'Inner',
  _ => '?',
};

// URLs look like /plain/b1/B or /home: main stack segments, then the active
// branch index and that branch's stack when a shell reports one.
class _Codec implements KaiselConfigCodec<_R> {
  const _Codec();

  @override
  Uri encode(KaiselConfig<_R> config) {
    final segments = [
      for (final route in config.mainStack)
        switch (route) {
          _Home() => 'home',
          _Plain() => 'plain',
          _Tabs() => 'tabs',
          _Group() => 'group',
        },
    ];
    if (config.nestedState case final KaiselShellConfig shell) {
      segments.add('b${shell.activeBranch}');
      segments.addAll(shell.activeBranchStack.map(_name));
    }
    return Uri(pathSegments: segments);
  }

  @override
  KaiselConfig<_R>? decode(Uri uri) {
    final segments = uri.pathSegments;
    final main = <_R>[];
    var i = 0;
    for (; i < segments.length && !segments[i].startsWith('b'); i++) {
      main.add(switch (segments[i]) {
        'plain' => const _Plain(),
        'tabs' => const _Tabs(),
        _ => const _Home(),
      });
    }
    return KaiselConfig<_R>(
      mainStack: main.isEmpty ? const [_Home()] : main,
      nestedState: i < segments.length
          ? KaiselShellConfig(
              activeBranch: int.parse(segments[i].substring(1)),
              activeBranchStack: [
                for (final s in segments.sublist(i + 1))
                  _names[s] ?? const _A(),
              ],
            )
          : null,
    );
  }
}

Widget _branchPage(BuildContext context, _T route) => switch (route) {
  _Inner() => KaiselShell<_T>(
    branchInitials: const [_A()],
    chromeBuilder: (context, i, content, _) => content,
    pageBuilder: _branchPage,
  ),
  _ => Scaffold(body: Text(_name(route))),
};

Widget _page(BuildContext context, _R route) => switch (route) {
  _Home() => const Scaffold(body: Text('home')),
  _Plain() => KaiselShell<_T>(
    branchInitials: const [_A(), _B()],
    chromeBuilder: (context, i, content, _) => content,
    pageBuilder: _branchPage,
  ),
  _Tabs() => KaiselBranchedShell.specs(
    branches: const [
      KaiselBranchSpec<_T>(initial: _Inner(), builder: _branchPage),
    ],
    chromeBuilder: (context, i, content, _) => content,
  ),
  _Group() => KaiselShell<_T>(
    branchInitials: const [_A()],
    chromeBuilder: (context, i, content, _) => content,
    pageBuilder: _branchPage,
  ),
};

class _App extends StatefulWidget {
  const _App();

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  late final KaiselRouterConfig<_R> config = KaiselRouterConfig<_R>(
    initial: const _Home(),
    codec: const _Codec(),
    restorationScopeId: 'main',
    builder: _page,
    modalBuilder: (context, route, content) => content,
  );

  @override
  void dispose() {
    config.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      MaterialApp.router(routerConfig: config, restorationScopeId: 'app');
}

KaiselRouterConfig<_R> _config(WidgetTester tester) =>
    tester.state<_AppState>(find.byType(_App)).config;

String _url(WidgetTester tester) => const _Codec()
    .encode(_config(tester).routerDelegate.currentConfiguration!)
    .path;

void main() {
  testWidgets('a deep link opens the branch and stack it names', (
    tester,
  ) async {
    tester.platformDispatcher.defaultRouteNameTestValue = '/plain/b0/A/ADeep';
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);

    await tester.pumpWidget(const _App());
    await tester.pumpAndSettle();

    expect(find.text('ADeep'), findsOneWidget);
  });

  testWidgets('a deep link can select a branch other than the first', (
    tester,
  ) async {
    tester.platformDispatcher.defaultRouteNameTestValue = '/plain/b1/B';
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);

    await tester.pumpWidget(const _App());
    await tester.pumpAndSettle();

    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('the URL follows pushes and branch switches', (tester) async {
    await tester.pumpWidget(const _App());
    await _config(tester).router.push(const _Plain());
    await tester.pumpAndSettle();
    expect(_url(tester), 'home/plain/b0/A');

    await tester.element(find.text('A')).push(const _ADeep());
    await tester.pumpAndSettle();
    expect(_url(tester), 'home/plain/b0/A/ADeep');

    tester.element(find.text('ADeep')).shell().switchTo(1);
    await tester.pumpAndSettle();
    expect(_url(tester), 'home/plain/b1/B');
  });

  testWidgets('the active branch stack survives a restart', (tester) async {
    await tester.pumpWidget(const _App());
    await _config(tester).router.push(const _Plain());
    await tester.pumpAndSettle();
    await tester.element(find.text('A')).push(const _ADeep());
    await tester.pumpAndSettle();

    await tester.restartAndRestore();
    await tester.pumpAndSettle();

    expect(find.text('ADeep'), findsOneWidget);
    expect(_config(tester).router.stack, const [_Home(), _Plain()]);
  });

  testWidgets('a branch this build does not mount is skipped', (tester) async {
    tester.platformDispatcher.defaultRouteNameTestValue = '/plain/b7/B';
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);

    await tester.pumpWidget(const _App());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('inside a branched shell, the outer shell keeps the URL', (
    tester,
  ) async {
    await tester.pumpWidget(const _App());
    await _config(tester).router.push(const _Tabs());
    await tester.pumpAndSettle();
    await tester.element(find.text('A')).push(const _ADeep());
    await tester.pumpAndSettle();

    // The URL holds one nested router. A KaiselShell under another shell
    // leaves it to the outer one, so existing URLs don't change.
    expect(_url(tester), 'home/tabs/b0/Inner');
  });

  testWidgets('a KaiselShell inside a modal flow stays out of the URL', (
    tester,
  ) async {
    await tester.pumpWidget(const _App());
    _config(tester).router.run(const _Group()).ignore();
    await tester.pumpAndSettle();
    await tester.element(find.text('A')).push(const _ADeep());
    await tester.pumpAndSettle();
    expect(find.text('ADeep'), findsOneWidget);

    expect(_url(tester), 'home');
  });
}
