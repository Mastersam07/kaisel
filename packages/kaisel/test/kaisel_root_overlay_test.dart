import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// Prototype coverage for the root overlay host: a root-navigator dialog must
// render ABOVE an active modal flow (not behind it, in the main navigator's
// overlay), and system back must dismiss that hosted dialog before unwinding
// the flow.

sealed class _App extends KaiselRoute {
  const _App();
}

final class _Home extends _App {
  const _Home();
}

final class _Sheet extends _App implements KaiselModalRoute<void> {
  const _Sheet();
}

class _FlowContent extends StatelessWidget {
  const _FlowContent();

  @override
  Widget build(BuildContext context) {
    // An opaque, full-surface flow that would hide a dialog rendered beneath
    // it in the main navigator's overlay.
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Center(
        child: ElevatedButton(
          // Default useRootNavigator: true → resolves the root overlay host,
          // which sits above this flow layer.
          onPressed: () => showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              content: const Text('loader'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('dismiss'),
                ),
              ],
            ),
          ),
          child: const Text('show-loader'),
        ),
      ),
    );
  }
}

void main() {
  KaiselRouterDelegate<_App> buildDelegate(KaiselRouter<_App> router) =>
      KaiselRouterDelegate<_App>(
        router: router,
        builder: (context, route) => switch (route) {
          _Home() => const Scaffold(body: Center(child: Text('home'))),
          _Sheet() => const _FlowContent(),
        },
        modalBuilder: (context, route, flowContent) => flowContent,
      );

  testWidgets('a root dialog renders above an active modal flow', (
    tester,
  ) async {
    final router = KaiselRouter<_App>(initial: const _Home());
    final delegate = buildDelegate(router);

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));

    unawaited(router.run<void>(const _Sheet()));
    await tester.pumpAndSettle();
    expect(router.hasActiveFlow, isTrue);
    expect(find.text('show-loader'), findsOneWidget);

    await tester.tap(find.text('show-loader'));
    await tester.pumpAndSettle();

    // The dialog is visible, and tapping its action (hit-testable above the
    // opaque flow) dismisses it — proving it sits on top, not behind.
    expect(find.text('loader'), findsOneWidget);
    expect(router.hasActiveFlow, isTrue);

    await tester.tap(find.text('dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('loader'), findsNothing);
    expect(router.hasActiveFlow, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });

  testWidgets('the customer scenario: a dialog shown via the app '
      'navigatorKey context appears above an active flow', (tester) async {
    // The app holds a GlobalKey it passes to the delegate (the key the
    // customer attaches to their config) and shows the loader with that key's
    // context — the case that used to render behind the flow.
    final navKey = GlobalKey<NavigatorState>();
    final router = KaiselRouter<_App>(initial: const _Home());
    final delegate = KaiselRouterDelegate<_App>(
      router: router,
      navigatorKey: navKey,
      builder: (context, route) => switch (route) {
        _Home() => const Scaffold(body: Center(child: Text('home'))),
        _Sheet() => const _FlowContent(),
      },
      modalBuilder: (context, route, flowContent) => flowContent,
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    unawaited(router.run<void>(const _Sheet()));
    await tester.pumpAndSettle();
    expect(router.hasActiveFlow, isTrue);

    // The customer's exact call: the navigatorKey's context, default
    // useRootNavigator: true. It resolves the root overlay host (an ancestor
    // of the main navigator), so the dialog lands above the flow.
    expect(navKey.currentContext, isNotNull);
    if (navKey.currentContext case final keyContext?) {
      unawaited(
        showDialog<void>(
          context: keyContext,
          builder: (_) => const AlertDialog(content: Text('loader')),
        ),
      );
    }
    await tester.pumpAndSettle();

    expect(find.text('loader'), findsOneWidget);

    // Confirm it really is above the flow: back dismisses the dialog, the flow
    // survives.
    final handled = await delegate.popRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.text('loader'), findsNothing);
    expect(router.hasActiveFlow, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });

  testWidgets('system back dismisses the hosted dialog before the flow', (
    tester,
  ) async {
    final router = KaiselRouter<_App>(initial: const _Home());
    final delegate = buildDelegate(router);

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    unawaited(router.run<void>(const _Sheet()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('show-loader'));
    await tester.pumpAndSettle();
    expect(find.text('loader'), findsOneWidget);

    // Back press goes through the delegate's popRoute → root overlay first.
    final handled = await delegate.popRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.text('loader'), findsNothing, reason: 'dialog dismissed');
    expect(router.hasActiveFlow, isTrue, reason: 'flow not unwound by back');

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });
}
