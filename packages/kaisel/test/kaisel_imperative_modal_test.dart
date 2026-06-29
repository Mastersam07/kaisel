import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// Regression guard for imperative overlays shown via a GlobalKey<NavigatorState>
// handed to the delegate, then driven through `key.currentContext`.
//
// `showDialog` / `showModalBottomSheet` push ROUTES, so `Navigator.pop` (via the
// same key context) dismisses them — but only while kaisel's main navigator is
// the top-most one. `showDialog` defaults `useRootNavigator: true` and
// `Navigator.pop` defaults `rootNavigator: false`; those resolve to the SAME
// navigator only when there is no navigator above the main one. Under
// `MaterialApp.router` there isn't, so both land on it. A 0.19.x build wrapped
// the app in an extra root overlay navigator, which split the two and made pop
// hit the page behind the dialog. These tests lock the single-navigator
// topology so that break can't silently return.
//
// SnackBars (ScaffoldMessenger) and toasts (OverlayEntry) are NOT routes: they
// render on top, but they are dismissed by their own API, not `Navigator.pop`.
// The last two tests pin that distinction.

sealed class _App extends KaiselRoute {
  const _App();
}

final class _Home extends _App {
  const _Home();
}

final class _Second extends _App {
  const _Second();
}

KaiselRouterDelegate<_App> _delegate(
  KaiselRouter<_App> router,
  GlobalKey<NavigatorState> appKey,
) => KaiselRouterDelegate<_App>(
  router: router,
  navigatorKey: appKey,
  builder: (context, route) => switch (route) {
    _Home() => const Scaffold(body: Center(child: Text('home'))),
    _Second() => const Scaffold(body: Center(child: Text('second'))),
  },
);

void main() {
  testWidgets('a dialog shows on top and pop via the key context dismisses it '
      '(not the page)', (tester) async {
    final appKey = GlobalKey<NavigatorState>();
    final router = KaiselRouter<_App>(initial: const _Home());
    final delegate = _delegate(router, appKey);

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    await router.push(const _Second());
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);

    final keyContext = appKey.currentContext;
    expect(keyContext, isNotNull);
    if (keyContext == null) return;

    // Show with the key's context (default useRootNavigator: true).
    unawaited(
      showDialog<void>(
        context: keyContext,
        builder: (_) => const AlertDialog(content: Text('dialog')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsOneWidget);

    // Pop with the same key context (default rootNavigator: false).
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
    final delegate = _delegate(router, appKey);

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

  testWidgets('a modal bottom sheet shows on top and pop via the key context '
      'dismisses it', (tester) async {
    final appKey = GlobalKey<NavigatorState>();
    final router = KaiselRouter<_App>(initial: const _Home());
    final delegate = _delegate(router, appKey);

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    await router.push(const _Second());
    await tester.pumpAndSettle();

    final keyContext = appKey.currentContext;
    if (keyContext == null) return;
    unawaited(
      showModalBottomSheet<void>(
        context: keyContext,
        builder: (_) =>
            const SizedBox(height: 120, child: Center(child: Text('sheet'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);

    Navigator.of(keyContext).pop();
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsNothing);
    expect(find.text('second'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });

  testWidgets('a snackbar renders on top; it is dismissed by the '
      'ScaffoldMessenger, not by Navigator.pop', (tester) async {
    final appKey = GlobalKey<NavigatorState>();
    final router = KaiselRouter<_App>(initial: const _Home());
    final delegate = _delegate(router, appKey);

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    final keyContext = appKey.currentContext;
    if (keyContext == null) return;

    ScaffoldMessenger.of(keyContext).showSnackBar(
      const SnackBar(content: Text('snack'), duration: Duration(minutes: 1)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.text('snack'), findsOneWidget);

    // A snackbar is not a route — its own API dismisses it.
    ScaffoldMessenger.of(keyContext).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(find.text('snack'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });

  testWidgets('an overlay toast renders on top and survives a route pop '
      '(removed by the entry, not the navigator)', (tester) async {
    final appKey = GlobalKey<NavigatorState>();
    final router = KaiselRouter<_App>(initial: const _Home());
    final delegate = _delegate(router, appKey);

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    await router.push(const _Second());
    await tester.pumpAndSettle();

    final overlay = appKey.currentState?.overlay;
    expect(overlay, isNotNull);
    final entry = OverlayEntry(
      builder: (_) => const Positioned(
        top: 0,
        left: 0,
        child: Text('toast', textDirection: TextDirection.ltr),
      ),
    );
    overlay?.insert(entry);
    await tester.pump();
    expect(find.text('toast'), findsOneWidget);

    // Show + pop a dialog via the key context: the dialog (a route) goes,
    // the toast (an overlay entry) stays — it isn't on the route stack.
    final keyContext = appKey.currentContext;
    if (keyContext == null) return;
    unawaited(
      showDialog<void>(
        context: keyContext,
        builder: (_) => const AlertDialog(content: Text('dialog')),
      ),
    );
    await tester.pumpAndSettle();
    Navigator.of(keyContext).pop();
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsNothing);
    expect(find.text('toast'), findsOneWidget);

    // Correct dismissal: remove the entry.
    entry.remove();
    await tester.pump();
    expect(find.text('toast'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });

  // context.pop() is kaisel's pop, and it is boundary-aware: called from inside
  // an imperative overlay (dialog/sheet) it closes that overlay; called from a
  // normal screen it pops the kaisel stack. See KaiselContextNavigation.pop.

  testWidgets('context.pop() inside a dialog closes the dialog, not the page', (
    tester,
  ) async {
    final appKey = GlobalKey<NavigatorState>();
    final router = KaiselRouter<_App>(initial: const _Home());
    final delegate = KaiselRouterDelegate<_App>(
      router: router,
      navigatorKey: appKey,
      builder: (context, route) => switch (route) {
        _Home() => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  content: const Text('dialog'),
                  actions: [
                    TextButton(
                      onPressed: () => dialogContext.pop(),
                      child: const Text('close'),
                    ),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
        _Second() => const Scaffold(body: Center(child: Text('second'))),
      },
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsOneWidget);

    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsNothing);
    expect(find.text('open'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });

  testWidgets('context.pop() inside a bottom sheet closes the sheet', (
    tester,
  ) async {
    final appKey = GlobalKey<NavigatorState>();
    final router = KaiselRouter<_App>(initial: const _Home());
    final delegate = KaiselRouterDelegate<_App>(
      router: router,
      navigatorKey: appKey,
      builder: (context, route) => switch (route) {
        _Home() => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (sheetContext) => SizedBox(
                  height: 120,
                  child: Center(
                    child: ElevatedButton(
                      onPressed: () => sheetContext.pop(),
                      child: const Text('close-sheet'),
                    ),
                  ),
                ),
              ),
              child: const Text('open-sheet'),
            ),
          ),
        ),
        _Second() => const Scaffold(body: Center(child: Text('second'))),
      },
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    await tester.tap(find.text('open-sheet'));
    await tester.pumpAndSettle();
    expect(find.text('close-sheet'), findsOneWidget);

    await tester.tap(find.text('close-sheet'));
    await tester.pumpAndSettle();
    expect(find.text('close-sheet'), findsNothing);
    expect(find.text('open-sheet'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });

  testWidgets('context.pop() from a screen pops the kaisel stack', (
    tester,
  ) async {
    final appKey = GlobalKey<NavigatorState>();
    final router = KaiselRouter<_App>(initial: const _Home());
    final delegate = KaiselRouterDelegate<_App>(
      router: router,
      navigatorKey: appKey,
      builder: (context, route) => switch (route) {
        _Home() => const Scaffold(body: Center(child: Text('home'))),
        _Second() => Scaffold(
          body: Center(
            child: Builder(
              builder: (screenContext) => ElevatedButton(
                onPressed: () => screenContext.pop(),
                child: const Text('pop-screen'),
              ),
            ),
          ),
        ),
      },
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    await router.push(const _Second());
    await tester.pumpAndSettle();
    expect(find.text('pop-screen'), findsOneWidget);

    await tester.tap(find.text('pop-screen'));
    await tester.pumpAndSettle();
    expect(find.text('pop-screen'), findsNothing);
    expect(find.text('home'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });
}
