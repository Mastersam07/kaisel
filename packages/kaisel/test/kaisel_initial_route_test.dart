import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

sealed class _R extends KaiselRoute {
  const _R();
}

final class _Splash extends _R {
  const _Splash();
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
  Uri encode(KaiselConfig<_R> config) => switch (config.mainStack.last) {
    _Splash() => Uri(path: '/splash'),
    _Home() => Uri(path: '/'),
    _Detail(:final id) => Uri(path: '/detail/$id'),
  };

  @override
  KaiselConfig<_R>? decode(Uri uri) => switch (uri.pathSegments) {
    [] || [''] => KaiselConfig<_R>(mainStack: const <_R>[_Home()]),
    ['splash'] => KaiselConfig<_R>(mainStack: const <_R>[_Splash()]),
    ['detail', final id] => KaiselConfig<_R>(
      mainStack: <_R>[const _Home(), _Detail(id)],
    ),
    _ => null,
  };
}

class _App extends StatefulWidget {
  const _App({this.onReady});

  final void Function(KaiselRouterConfig<_R> config)? onReady;

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  late final KaiselRouterConfig<_R> config = KaiselRouterConfig<_R>(
    initial: const _Splash(),
    codec: const _Codec(),
    builder: (context, route) => switch (route) {
      _Splash() => const Scaffold(body: Center(child: Text('splash'))),
      _Home() => const Scaffold(body: Center(child: Text('home'))),
      _Detail(:final id) => Scaffold(body: Center(child: Text('detail $id'))),
    },
  );

  @override
  void initState() {
    super.initState();
    widget.onReady?.call(config);
  }

  @override
  void dispose() {
    config.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      MaterialApp.router(routerConfig: config);
}

void main() {
  testWidgets('a bare launch honors initial: over the decoded default route', (
    tester,
  ) async {
    await tester.pumpWidget(const _App());
    await tester.pumpAndSettle();

    expect(find.text('splash'), findsOneWidget);
    expect(find.text('home'), findsNothing);
  });

  testWidgets('a cold-start deep link still overrides initial:', (
    tester,
  ) async {
    tester.platformDispatcher.defaultRouteNameTestValue = '/detail/x';
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);

    await tester.pumpWidget(const _App());
    await tester.pumpAndSettle();

    expect(find.text('detail x'), findsOneWidget);
    expect(find.text('splash'), findsNothing);
  });

  testWidgets('splash drives the next route itself once shown', (tester) async {
    late final KaiselRouterConfig<_R> config;
    await tester.pumpWidget(_App(onReady: (c) => config = c));
    await tester.pumpAndSettle();

    expect(find.text('splash'), findsOneWidget);

    await config.router.set(const <_R>[_Home()]);
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(find.text('splash'), findsNothing);
  });
}
