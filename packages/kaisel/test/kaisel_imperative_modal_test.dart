import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// Regression guard for the imperative-modal interop pattern some apps use: a
// GlobalKey<NavigatorState> handed to the delegate, then
// `key.currentContext` used to show a dialog AND to pop it.
//
// `showDialog` defaults `useRootNavigator: true`; `Navigator.pop` defaults
// `rootNavigator: false`. Those resolve to the SAME navigator only while
// kaisel's main navigator is the top-most one. Under `MaterialApp.router` it
// is, so show + pop both land on it — the dialog is dismissed, not the page.
//
// A 0.19.x build wrapped the app in an extra root overlay navigator, which
// made `useRootNavigator: true` resolve upward (to the overlay) while pop
// stayed on the main nav — so pop hit the page behind the dialog. This test
// locks in that the single-navigator topology is preserved, so that break
// can't silently return.

sealed class _App extends KaiselRoute {
  const _App();
}

final class _Home extends _App {
  const _Home();
}

final class _Second extends _App {
  const _Second();
}

void main() {
  testWidgets('show + pop via the navigatorKey context resolve to one '
      'navigator (dialog dismissed, page survives)', (tester) async {
    final appKey = GlobalKey<NavigatorState>();
    final router = KaiselRouter<_App>(initial: const _Home());
    final delegate = KaiselRouterDelegate<_App>(
      router: router,
      navigatorKey: appKey,
      builder: (context, route) => switch (route) {
        _Home() => const Scaffold(body: Center(child: Text('home'))),
        _Second() => const Scaffold(body: Center(child: Text('second'))),
      },
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    await router.push(const _Second());
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);

    final keyContext = appKey.currentContext;
    expect(keyContext, isNotNull);
    if (keyContext == null) return;

    // The customer's exact shape: show with the key's context (default
    // useRootNavigator: true).
    unawaited(
      showDialog<void>(
        context: keyContext,
        builder: (_) => const AlertDialog(content: Text('dialog')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsOneWidget);

    // Pop with the same key context (default rootNavigator: false) — must
    // dismiss the dialog, NOT the page behind it.
    Navigator.of(keyContext).pop();
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsNothing);
    expect(find.text('second'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });

  testWidgets('system back dismisses the dialog before unwinding the stack', (
    tester,
  ) async {
    final appKey = GlobalKey<NavigatorState>();
    final router = KaiselRouter<_App>(initial: const _Home());
    final delegate = KaiselRouterDelegate<_App>(
      router: router,
      navigatorKey: appKey,
      builder: (context, route) => switch (route) {
        _Home() => const Scaffold(body: Center(child: Text('home'))),
        _Second() => const Scaffold(body: Center(child: Text('second'))),
      },
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    await router.push(const _Second());
    await tester.pumpAndSettle();

    final keyContext = appKey.currentContext;
    if (keyContext == null) return;
    unawaited(
      showDialog<void>(
        context: keyContext,
        builder: (_) => const AlertDialog(content: Text('dialog')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsOneWidget);

    expect(await delegate.popRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsNothing);
    expect(find.text('second'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });
}
