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
  const _Detail();
}

void main() {
  testWidgets('closes a drawer instead of popping the screen under it', (
    tester,
  ) async {
    final router = KaiselRouter<_R>(initial: const _Home());
    late BuildContext screenContext;
    final delegate = KaiselRouterDelegate<_R>(
      router: router,
      builder: (context, route) => switch (route) {
        _Home() => const Scaffold(body: Center(child: Text('home'))),
        _Detail() => Scaffold(
          drawer: const Drawer(child: Text('drawer')),
          body: Builder(
            builder: (context) {
              screenContext = context;
              return ElevatedButton(
                onPressed: () => Scaffold.of(context).openDrawer(),
                child: const Text('open-drawer'),
              );
            },
          ),
        ),
      },
    );
    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));

    await router.push(const _Detail());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open-drawer'));
    await tester.pumpAndSettle();
    expect(find.text('drawer'), findsOneWidget);

    final handled = await screenContext.maybePop();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.text('drawer'), findsNothing);
    expect(router.stack, const [_Home(), _Detail()]);
  });

  testWidgets('respects a PopScope veto and reports it handled', (
    tester,
  ) async {
    final router = KaiselRouter<_R>(initial: const _Home());
    var vetoRuns = 0;
    bool? result;
    final delegate = KaiselRouterDelegate<_R>(
      router: router,
      builder: (context, route) => switch (route) {
        _Home() => const Scaffold(body: Center(child: Text('home'))),
        _Detail() => PopScope<Object?>(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) => vetoRuns++,
          child: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async => result = await context.maybePop(),
                child: const Text('maybe-pop'),
              ),
            ),
          ),
        ),
      },
    );
    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));

    await router.push(const _Detail());
    await tester.pumpAndSettle();
    await tester.tap(find.text('maybe-pop'));
    await tester.pumpAndSettle();

    expect(vetoRuns, 1);
    expect(result, isTrue);
    expect(router.stack, const [_Home(), _Detail()]);
  });

  testWidgets('pops the screen when nothing else claims the gesture', (
    tester,
  ) async {
    final router = KaiselRouter<_R>(initial: const _Home());
    final delegate = KaiselRouterDelegate<_R>(
      router: router,
      builder: (context, route) => switch (route) {
        _Home() => const Scaffold(body: Center(child: Text('home'))),
        _Detail() => Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => context.maybePop(),
              child: const Text('maybe-pop'),
            ),
          ),
        ),
      },
    );
    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));

    await router.push(const _Detail());
    await tester.pumpAndSettle();
    await tester.tap(find.text('maybe-pop'));
    await tester.pumpAndSettle();

    expect(router.stack, const [_Home()]);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('unwinds an adaptive layout that collapsed the visible pages', (
    tester,
  ) async {
    final router = KaiselRouter<_R>(initial: const _Home());
    final delegate = KaiselRouterDelegate<_R>.adaptive(
      router: router,
      builder: (context, route, stack) => switch ((route, stack.previous)) {
        (_Detail(), _Home()) => KaiselAbsorbingPage(
          absorbing: 1,
          widget: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => context.maybePop(),
                child: const Text('maybe-pop'),
              ),
            ),
          ),
        ),
        _ => const KaiselStandalonePage(
          Scaffold(body: Center(child: Text('home'))),
        ),
      },
    );
    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));

    await router.push(const _Detail());
    await tester.pumpAndSettle();

    await tester.tap(find.text('maybe-pop'));
    await tester.pumpAndSettle();

    expect(router.stack, const [_Home()]);
  });
}
