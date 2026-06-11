import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

sealed class _R extends KaiselRoute {
  const _R();
}

final class _Home extends _R {
  const _Home();
}

void main() {
  testWidgets(
    'a passed navigatorKey drives the main navigator and is exposed',
    (tester) async {
      final key = GlobalKey<NavigatorState>();
      final config = KaiselRouterConfig<_R>(
        initial: const _Home(),
        navigatorKey: key,
        builder: (context, route) =>
            const Scaffold(body: Center(child: Text('home'))),
      );
      addTearDown(config.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: config));

      expect(config.navigatorKey, same(key));
      expect(key.currentState, isNotNull);
      expect(config.navigator, same(key.currentState));
    },
  );

  testWidgets(
    'a navigatorKey is auto-created and exposed when none is passed',
    (tester) async {
      final config = KaiselRouterConfig<_R>(
        initial: const _Home(),
        builder: (context, route) =>
            const Scaffold(body: Center(child: Text('home'))),
      );
      addTearDown(config.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: config));

      expect(config.navigatorKey, isNotNull);
      expect(config.navigator, isNotNull);
      expect(config.navigator, same(config.navigatorKey.currentState));
    },
  );
}
