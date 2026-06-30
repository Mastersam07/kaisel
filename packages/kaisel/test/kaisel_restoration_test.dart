import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

sealed class _R extends KaiselRoute {
  const _R();
}

final class _Home extends _R {
  const _Home();
}

final class _Detail extends _R {
  const _Detail(this.id);

  final String id;

  @override
  List<Object?> get props => <Object?>[id];
}

class _Codec implements KaiselConfigCodec<_R> {
  const _Codec();

  @override
  Uri encode(KaiselConfig<_R> config) => Uri(
    pathSegments: <String>[
      for (final route in config.mainStack)
        switch (route) {
          _Home() => 'home',
          _Detail(:final id) => 'detail-$id',
        },
    ],
  );

  @override
  KaiselConfig<_R>? decode(Uri uri) {
    final stack = <_R>[];
    for (final segment in uri.pathSegments) {
      final route = switch (segment) {
        'home' => const _Home(),
        _ when segment.startsWith('detail-') => _Detail(
          segment.substring('detail-'.length),
        ),
        _ => null,
      };
      if (route == null) return null;
      stack.add(route);
    }
    return KaiselConfig<_R>(
      mainStack: stack.isEmpty ? const <_R>[_Home()] : stack,
    );
  }
}

class _CodecApp extends StatefulWidget {
  const _CodecApp({this.scopeId});

  final String? scopeId;

  @override
  State<_CodecApp> createState() => _CodecAppState();
}

class _CodecAppState extends State<_CodecApp> {
  late final KaiselRouterConfig<_R> config = KaiselRouterConfig<_R>(
    initial: const _Home(),
    codec: const _Codec(),
    builder: (context, route) => switch (route) {
      _Home() => const Scaffold(body: Center(child: Text('home'))),
      _Detail(:final id) => Scaffold(body: Center(child: Text('detail $id'))),
    },
  );

  @override
  void dispose() {
    config.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: config,
    restorationScopeId: widget.scopeId,
  );
}

KaiselRouter<_R> _routerOf(WidgetTester tester) =>
    tester.state<_CodecAppState>(find.byType(_CodecApp)).config.router;

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> with RestorationMixin {
  final RestorableInt _count = RestorableInt(0);

  @override
  String get restorationId => 'counter';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_count, 'count');
  }

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text('count: ${_count.value}'),
      ElevatedButton(
        onPressed: () => setState(() => _count.value++),
        child: const Text('inc'),
      ),
    ],
  );
}

class _CounterApp extends StatefulWidget {
  const _CounterApp({this.navScopeId});

  final String? navScopeId;

  @override
  State<_CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<_CounterApp> {
  late final KaiselRouterConfig<_R> config = KaiselRouterConfig<_R>(
    initial: const _Home(),
    restorationScopeId: widget.navScopeId,
    builder: (context, route) => switch (route) {
      _Home() => const Scaffold(body: Center(child: _Counter())),
      _Detail() => const Scaffold(),
    },
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

sealed class _Tab extends KaiselRoute {
  const _Tab();
}

final class _TabRoot extends _Tab {
  const _TabRoot();
}

class _ShellApp extends StatefulWidget {
  const _ShellApp();

  @override
  State<_ShellApp> createState() => _ShellAppState();
}

class _ShellAppState extends State<_ShellApp> {
  late final KaiselRouterConfig<_R> config = KaiselRouterConfig<_R>(
    initial: const _Home(),
    restorationScopeId: 'main',
    builder: (context, route) => switch (route) {
      _Home() => KaiselShell<_Tab>(
        branchInitials: const <_Tab>[_TabRoot()],
        pageBuilder: (context, route) => switch (route) {
          _TabRoot() => const Scaffold(body: Center(child: _Counter())),
        },
        chromeBuilder: (context, active, branchContent, switchBranch) =>
            branchContent,
      ),
      _Detail() => const Scaffold(),
    },
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

sealed class _BR extends KaiselRoute {
  const _BR();
}

final class _BHome extends _BR {
  const _BHome();
}

final class _BDetail extends _BR {
  const _BDetail(this.id);

  final String id;

  @override
  List<Object?> get props => <Object?>[id];
}

final class _BBad extends _BR {
  const _BBad();

  @override
  List<Object?> get props => <Object?>[DateTime(2020)];
}

class _BucketApp extends StatefulWidget {
  const _BucketApp({required this.restore});

  final KaiselRouteRestorer<_BR> restore;

  @override
  State<_BucketApp> createState() => _BucketAppState();
}

class _BucketAppState extends State<_BucketApp> {
  late final KaiselRouterConfig<_BR> config = KaiselRouterConfig<_BR>(
    initial: const _BHome(),
    restoreRoute: widget.restore,
    builder: (context, route) => switch (route) {
      _BHome() => const Scaffold(body: Center(child: Text('home'))),
      _BDetail(:final id) => Scaffold(body: Center(child: Text('detail $id'))),
      _BBad() => const Scaffold(body: Center(child: Text('bad'))),
    },
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

_BR _restoreBR(String name, List<Object?> props) => switch (name) {
  '_BDetail' => _BDetail(props[0] as String),
  _ => const _BHome(),
};

KaiselRouter<_BR> _bucketRouterOf(WidgetTester tester) =>
    tester.state<_BucketAppState>(find.byType(_BucketApp)).config.router;

void main() {
  testWidgets('a codec app restores the main stack across a restart', (
    tester,
  ) async {
    await tester.pumpWidget(const _CodecApp(scopeId: 'app'));
    final before = _routerOf(tester);
    await before.push(const _Detail('x'));
    await tester.pumpAndSettle();
    expect(find.text('detail x'), findsOneWidget);

    await tester.restartAndRestore();
    await tester.pumpAndSettle();

    final after = _routerOf(tester);
    expect(
      identical(after, before),
      isFalse,
      reason:
          'a real restart builds a fresh router; the stack came from '
          'restoration, not a surviving object',
    );
    expect(find.text('detail x'), findsOneWidget);
    expect(after.stack, <_R>[const _Home(), const _Detail('x')]);
  });

  testWidgets('restores a deep stack faithfully, not just the top', (
    tester,
  ) async {
    await tester.pumpWidget(const _CodecApp(scopeId: 'app'));
    await _routerOf(tester).push(const _Detail('a'));
    await _routerOf(tester).push(const _Detail('b'));
    await tester.pumpAndSettle();

    await tester.restartAndRestore();
    await tester.pumpAndSettle();

    expect(_routerOf(tester).stack, <_R>[
      const _Home(),
      const _Detail('a'),
      const _Detail('b'),
    ]);
  });

  testWidgets("a main page's inner state restores when the navigator has a "
      'restorationScopeId', (tester) async {
    await tester.pumpWidget(const _CounterApp(navScopeId: 'main'));
    await tester.tap(find.text('inc'));
    await tester.pumpAndSettle();
    expect(find.text('count: 1'), findsOneWidget);

    await tester.restartAndRestore();
    await tester.pumpAndSettle();

    expect(find.text('count: 1'), findsOneWidget);
  });

  testWidgets('without the navigator restorationScopeId, inner state is lost', (
    tester,
  ) async {
    await tester.pumpWidget(const _CounterApp());
    await tester.tap(find.text('inc'));
    await tester.pumpAndSettle();
    expect(find.text('count: 1'), findsOneWidget);

    await tester.restartAndRestore();
    await tester.pumpAndSettle();

    expect(find.text('count: 0'), findsOneWidget);
  });

  testWidgets('a shell branch page restores its inner state across a restart', (
    tester,
  ) async {
    await tester.pumpWidget(const _ShellApp());
    await tester.tap(find.text('inc'));
    await tester.pumpAndSettle();
    expect(find.text('count: 1'), findsOneWidget);

    await tester.restartAndRestore();
    await tester.pumpAndSettle();

    expect(find.text('count: 1'), findsOneWidget);
  });

  testWidgets('a codec-less app restores the main stack via restoreRoute', (
    tester,
  ) async {
    await tester.pumpWidget(const _BucketApp(restore: _restoreBR));
    await _bucketRouterOf(tester).push(const _BDetail('x'));
    await tester.pumpAndSettle();
    expect(find.text('detail x'), findsOneWidget);

    await tester.restartAndRestore();
    await tester.pumpAndSettle();

    expect(find.text('detail x'), findsOneWidget);
    expect(_bucketRouterOf(tester).stack, <_BR>[
      const _BHome(),
      const _BDetail('x'),
    ]);
  });

  testWidgets('a route whose props are not JSON-able is dropped, not crashed', (
    tester,
  ) async {
    await tester.pumpWidget(const _BucketApp(restore: _restoreBR));
    await _bucketRouterOf(tester).push(const _BBad());
    await tester.pumpAndSettle();

    await tester.restartAndRestore();
    await tester.pumpAndSettle();

    expect(_bucketRouterOf(tester).stack, <_BR>[const _BHome()]);
  });

  testWidgets('a restoreRoute that returns a mismatching route falls back', (
    tester,
  ) async {
    await tester.pumpWidget(
      _BucketApp(restore: (name, props) => const _BHome()),
    );
    await _bucketRouterOf(tester).push(const _BDetail('x'));
    await tester.pumpAndSettle();

    await tester.restartAndRestore();
    await tester.pumpAndSettle();

    expect(_bucketRouterOf(tester).stack, <_BR>[
      const _BHome(),
      const _BHome(),
    ]);
  });
}
