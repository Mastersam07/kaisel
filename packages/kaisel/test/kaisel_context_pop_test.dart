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
  testWidgets('context.pop on a kaisel page runs through the guarded router', (
    tester,
  ) async {
    var guardRuns = 0;
    final router = KaiselRouter<_R>(
      initial: const _Home(),
      guards: <KaiselGuard<_R>>[
        (current, proposed) {
          guardRuns++;
          return proposed;
        },
      ],
    );
    final delegate = KaiselRouterDelegate<_R>(
      router: router,
      builder: (context, route) => switch (route) {
        _Home() => const Scaffold(body: Center(child: Text('home'))),
        _Detail() => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => context.pop(),
              child: const Text('pop-route'),
            ),
          ),
        ),
      },
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    await router.push(const _Detail());
    await tester.pumpAndSettle();
    expect(router.stack.length, 2);
    final before = guardRuns;

    await tester.tap(find.text('pop-route'));
    await tester.pumpAndSettle();

    expect(router.stack, <_R>[const _Home()]);
    expect(guardRuns, greaterThan(before));

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });

  testWidgets('context.pop inside a bottom sheet closes the sheet, not the '
      'route beneath it', (tester) async {
    final router = KaiselRouter<_R>(initial: const _Home());
    final delegate = KaiselRouterDelegate<_R>(
      router: router,
      builder: (context, route) => switch (route) {
        _Home() => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (sheetContext) => ElevatedButton(
                  onPressed: () => sheetContext.pop(),
                  child: const Text('close-sheet'),
                ),
              ),
              child: const Text('open-sheet'),
            ),
          ),
        ),
        _Detail() => const Scaffold(),
      },
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    await tester.tap(find.text('open-sheet'));
    await tester.pumpAndSettle();
    expect(find.text('close-sheet'), findsOneWidget);

    await tester.tap(find.text('close-sheet'));
    await tester.pumpAndSettle();

    expect(find.text('close-sheet'), findsNothing);
    expect(router.stack, <_R>[const _Home()]);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });

  testWidgets('context.pop inside a dialog closes the dialog, not the route', (
    tester,
  ) async {
    final router = KaiselRouter<_R>(initial: const _Home());
    final delegate = KaiselRouterDelegate<_R>(
      router: router,
      builder: (context, route) => switch (route) {
        _Home() => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  content: ElevatedButton(
                    onPressed: () => dialogContext.pop(),
                    child: const Text('close-dialog'),
                  ),
                ),
              ),
              child: const Text('open-dialog'),
            ),
          ),
        ),
        _Detail() => const Scaffold(),
      },
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    await tester.tap(find.text('open-dialog'));
    await tester.pumpAndSettle();
    expect(find.text('close-dialog'), findsOneWidget);

    await tester.tap(find.text('close-dialog'));
    await tester.pumpAndSettle();

    expect(find.text('close-dialog'), findsNothing);
    expect(router.stack, <_R>[const _Home()]);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });
}
