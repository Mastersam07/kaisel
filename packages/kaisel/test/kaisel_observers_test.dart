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

class _RecordingObserver extends NavigatorObserver {
  int pushes = 0;
  int pops = 0;
  String? lastPushedName;
  Object? lastPushedArguments;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    lastPushedName = route.settings.name;
    lastPushedArguments = route.settings.arguments;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}

void main() {
  testWidgets('the main navigator forwards push/pop to factory observers', (
    tester,
  ) async {
    final created = <_RecordingObserver>[];
    final router = KaiselRouter<_R>(initial: const _Home());
    final delegate = KaiselRouterDelegate<_R>(
      router: router,
      observers: () {
        final o = _RecordingObserver();
        created.add(o);
        return <NavigatorObserver>[o];
      },
      builder: (context, route) => switch (route) {
        _Home() => const Scaffold(body: Text('home')),
        _Detail() => const Scaffold(body: Text('detail')),
      },
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    expect(
      created,
      hasLength(1),
      reason: 'one observer for the main navigator',
    );
    final main = created.single;
    final initialPushes = main.pushes;
    expect(initialPushes, greaterThan(0));

    await router.push(const _Detail('a'));
    await tester.pumpAndSettle();
    expect(main.pushes, initialPushes + 1);
    expect(main.lastPushedName, '_Detail');
    expect(main.lastPushedArguments, const _Detail('a'));

    await router.pop();
    await tester.pumpAndSettle();
    expect(main.pops, greaterThan(0));

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });

  testWidgets('each nested navigator gets its own fresh observer instance', (
    tester,
  ) async {
    final created = <_RecordingObserver>[];
    List<NavigatorObserver> factory() {
      final o = _RecordingObserver();
      created.add(o);
      return <NavigatorObserver>[o];
    }

    final mainRouter = KaiselRouter<_R>(initial: const _Home());
    final innerRouter = KaiselRouter<_R>(initial: const _Home());
    final innerKey = GlobalKey<NavigatorState>();

    final delegate = KaiselRouterDelegate<_R>(
      router: mainRouter,
      observers: factory,
      // The main screen embeds a second navigator — the stand-in for a shell
      // branch / module. It reads the same KaiselObserverScope the delegate
      // installs, so it should get its own fresh observer.
      builder: (context, route) => Scaffold(
        body: KaiselInnerNavigator<_R>(
          router: innerRouter,
          navigatorKey: innerKey,
          pageBuilder: (context, r) => const SizedBox.shrink(),
        ),
      ),
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    expect(created, hasLength(2), reason: 'main navigator + the nested one');
    expect(
      identical(created[0], created[1]),
      isFalse,
      reason: 'each navigator gets its own instance',
    );

    final mainObs = created[0];
    final innerObs = created[1];
    final mainBefore = mainObs.pushes;
    final innerBefore = innerObs.pushes;

    await innerRouter.push(const _Detail('x'));
    await tester.pumpAndSettle();

    expect(
      innerObs.pushes,
      innerBefore + 1,
      reason: 'the nested observer sees nested navigation',
    );
    expect(
      mainObs.pushes,
      mainBefore,
      reason: 'the main observer does not see nested navigation',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    mainRouter.dispose();
    innerRouter.dispose();
  });

  testWidgets('KaiselRouterConfig forwards the observers builder', (
    tester,
  ) async {
    final created = <_RecordingObserver>[];
    final config = KaiselRouterConfig<_R>(
      initial: const _Home(),
      observers: () {
        final o = _RecordingObserver();
        created.add(o);
        return <NavigatorObserver>[o];
      },
      builder: (context, route) => const Scaffold(body: SizedBox.shrink()),
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: config));
    expect(created, isNotEmpty);
    final obs = created.first;
    final before = obs.pushes;

    await config.router.push(const _Detail('b'));
    await tester.pumpAndSettle();
    expect(obs.pushes, before + 1);

    await tester.pumpWidget(const SizedBox.shrink());
    config.dispose();
  });

  testWidgets('no observers builder leaves navigation working', (tester) async {
    final router = KaiselRouter<_R>(initial: const _Home());
    final delegate = KaiselRouterDelegate<_R>(
      router: router,
      builder: (context, route) => const Scaffold(body: SizedBox.shrink()),
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    await router.push(const _Detail('c'));
    await tester.pumpAndSettle();
    expect(find.byType(Navigator), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });
}
