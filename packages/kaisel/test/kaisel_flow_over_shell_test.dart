import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// A flow run on the main router covers a shell's chrome under Option C, because
// the flow is a route on the main navigator and the shell is a page beneath it
// — no root-navigator targeting API required for the common case.

sealed class _App extends KaiselRoute {
  const _App();
}

final class _ShellHost extends _App {
  const _ShellHost();
}

final class _PaymentFlow extends _App implements KaiselModalRoute<bool> {
  const _PaymentFlow();
}

sealed class _Tab extends KaiselRoute {
  const _Tab();
}

final class _TabA extends _Tab {
  const _TabA();
}

final class _TabB extends _Tab {
  const _TabB();
}

void main() {
  testWidgets('a flow run on the main router renders over a shell and '
      'unwinds back to it', (tester) async {
    final router = KaiselRouter<_App>(initial: const _ShellHost());
    final delegate = KaiselRouterDelegate<_App>(
      router: router,
      builder: (context, route) => switch (route) {
        _ShellHost() => KaiselShell<_Tab>(
          branchInitials: const [_TabA(), _TabB()],
          pageBuilder: (context, tab) => Scaffold(
            body: Center(child: Text(tab is _TabA ? 'tab-a' : 'tab-b')),
          ),
          chromeBuilder: (context, active, content, switchBranch) => Scaffold(
            body: content,
            bottomNavigationBar: TextButton(
              onPressed: () => switchBranch(1),
              child: const Text('go-b'),
            ),
          ),
        ),
        _PaymentFlow() => Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => context.completeFlow<bool>(true),
                child: const Text('pay-done'),
              ),
            ),
          ),
        ),
      },
      // An opaque, full-surface modal: if the flow rendered beneath the shell
      // it would be hidden, and its button would not be tappable.
      modalBuilder: (context, route, flowContent) =>
          Material(color: const Color(0xFF202020), child: flowContent),
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    expect(find.text('tab-a'), findsOneWidget);
    expect(find.text('go-b'), findsOneWidget);

    final result = router.run<bool>(const _PaymentFlow());
    await tester.pumpAndSettle();

    // The flow is on top of the shell (chrome included): its button is
    // hit-testable.
    expect(find.text('pay-done'), findsOneWidget);
    await tester.tap(find.text('pay-done'));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
    expect(router.hasActiveFlow, isFalse);
    // Back on the shell, with its chrome.
    expect(find.text('tab-a'), findsOneWidget);
    expect(find.text('go-b'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });
}
