import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

sealed class _R extends KaiselRoute {
  const _R();
}

final class _Home extends _R {
  const _Home();
}

final class _Picker extends _R {
  const _Picker();
}

/// Records the route names the navigator pushes, so a test can assert that a
/// pushForResult screen is observed by the app's shared observer — the thing a
/// modal flow's separate navigator would miss.
class _RecordingObserver extends NavigatorObserver {
  final List<String?> pushed = <String?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route.settings.name);
  }
}

void main() {
  testWidgets('pushForResult lives on the main stack and returns a typed '
      'value via context.pop(result)', (tester) async {
    final router = KaiselRouter<_R>(initial: const _Home());
    String? received;

    final delegate = KaiselRouterDelegate<_R>(
      router: router,
      builder: (context, route) => switch (route) {
        _Home() => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                received = await context.pushForResult<String>(const _Picker());
              },
              child: const Text('pick'),
            ),
          ),
        ),
        _Picker() => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => context.pop('chosen-value'),
              child: const Text('choose'),
            ),
          ),
        ),
      },
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();

    // The picker is a normal route on the main stack, not a modal flow.
    expect(router.stack, <_R>[const _Home(), const _Picker()]);
    expect(router.hasActiveFlow, isFalse);

    await tester.tap(find.text('choose'));
    await tester.pumpAndSettle();

    expect(received, 'chosen-value');
    expect(router.stack, <_R>[const _Home()]);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });

  testWidgets('a shared observer sees a pushForResult route, and a '
      'root-navigator dialog shows above it', (tester) async {
    final observer = _RecordingObserver();
    final router = KaiselRouter<_R>(initial: const _Home());

    final delegate = KaiselRouterDelegate<_R>(
      router: router,
      observers: () => [observer],
      builder: (context, route) => switch (route) {
        _Home() => const Scaffold(body: Center(child: Text('home'))),
        _Picker() => Scaffold(
          body: Center(
            child: ElevatedButton(
              // Default useRootNavigator: true — targets the main navigator.
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(content: Text('loader')),
              ),
              child: const Text('show-loader'),
            ),
          ),
        ),
      },
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    // Do not await: pushForResult only completes when the picker is popped,
    // which this test never does. We only care that the screen is shown,
    // observed, and can host a dialog.
    unawaited(router.pushForResult<String>(const _Picker()));
    await tester.pumpAndSettle();

    // The shared observer instance saw the pushed route — unlike a flow, whose
    // separate navigator gets a different observer instance.
    expect(observer.pushed, contains('_Picker'));

    await tester.tap(find.text('show-loader'));
    await tester.pumpAndSettle();
    // The root-navigator dialog renders (it is not hidden behind a flow layer).
    expect(find.text('loader'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });

  testWidgets('closing a dialog with a result does not leak into the '
      'underlying screen result', (tester) async {
    final router = KaiselRouter<_R>(initial: const _Home());
    String? received = 'sentinel';

    final delegate = KaiselRouterDelegate<_R>(
      router: router,
      builder: (context, route) => switch (route) {
        _Home() => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                received = await context.pushForResult<String>(const _Picker());
              },
              child: const Text('pick'),
            ),
          ),
        ),
        _Picker() => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (dialogContext) => ElevatedButton(
                      onPressed: () => dialogContext.pop('dialog-value'),
                      child: const Text('close-dialog'),
                    ),
                  ),
                  child: const Text('open-dialog'),
                ),
                ElevatedButton(
                  onPressed: () => context.pop(),
                  child: const Text('cancel'),
                ),
              ],
            ),
          ),
        ),
      },
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();

    // Close a dialog with a result — it belongs to the dialog, not the screen.
    await tester.tap(find.text('open-dialog'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('close-dialog'));
    await tester.pumpAndSettle();

    // Cancelling the screen with no value resolves the awaiter with null,
    // not the dialog's leftover result.
    await tester.tap(find.text('cancel'));
    await tester.pumpAndSettle();
    expect(received, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });

  testWidgets('a pending result resolves null when the delegate restores a '
      'new path', (tester) async {
    final router = KaiselRouter<_R>(initial: const _Home());
    final delegate = KaiselRouterDelegate<_R>(
      router: router,
      builder: (context, route) => switch (route) {
        _Home() => const Scaffold(body: Center(child: Text('home'))),
        _Picker() => const Scaffold(body: Center(child: Text('picker'))),
      },
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    final future = router.pushForResult<String>(const _Picker());
    await tester.pumpAndSettle();
    expect(find.text('picker'), findsOneWidget);

    // The exact callback Flutter invokes on restoration or a new deep link.
    await delegate.setNewRoutePath(
      KaiselConfig<_R>(mainStack: const [_Home()]),
    );
    await tester.pumpAndSettle();

    expect(await future.timeout(const Duration(seconds: 1)), isNull);
    expect(find.text('home'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });
}
