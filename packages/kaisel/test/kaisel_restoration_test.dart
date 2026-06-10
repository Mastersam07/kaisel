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
    pageWrapper: (ctx) => MaterialPage<void>(
      key: ctx.key,
      restorationId: 'page',
      child: ctx.child,
    ),
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
}
