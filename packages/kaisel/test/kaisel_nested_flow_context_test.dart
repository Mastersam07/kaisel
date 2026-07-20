import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// Regression test for #55: inside a flow screen, `context.router<R>()`
// resolves to the flow's sub-router. Calling `run` on it must still open
// the nested flow on the host's overlay stack — not vanish into a flow
// list nothing renders.

sealed class _App extends KaiselRoute {
  const _App();
}

final class _Home extends _App {
  const _Home();
}

final class _OuterFlow extends _App implements KaiselModalRoute<bool> {
  const _OuterFlow();
}

final class _InnerFlow extends _App implements KaiselModalRoute<String> {
  const _InnerFlow();
}

class _OuterScreen extends StatefulWidget {
  const _OuterScreen();

  @override
  State<_OuterScreen> createState() => _OuterScreenState();
}

class _OuterScreenState extends State<_OuterScreen> {
  String? received;

  Future<void> _openInner() async {
    // The natural call from inside a flow: context resolves the sub-router.
    final value = await context.router<_App>().run<String>(const _InnerFlow());
    if (!mounted) return;
    setState(() => received = value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('outer-flow'),
        if (received case final value?) Text('received-$value'),
        TextButton(onPressed: _openInner, child: const Text('open-inner')),
      ],
    );
  }
}

class _InnerScreen extends StatelessWidget {
  const _InnerScreen();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('inner-flow'),
        TextButton(
          onPressed: () => context.completeFlow<String>('card-42'),
          child: const Text('save'),
        ),
      ],
    );
  }
}

void main() {
  testWidgets('run from inside a flow opens a nested flow on the host', (
    tester,
  ) async {
    final router = KaiselRouter<_App>(initial: const _Home());
    final delegate = KaiselRouterDelegate<_App>(
      router: router,
      builder: (context, route) => switch (route) {
        _Home() => const Scaffold(body: Center(child: Text('home'))),
        _OuterFlow() => const _OuterScreen(),
        _InnerFlow() => const _InnerScreen(),
      },
      modalBuilder: (context, route, child) => ColoredBox(
        color: const Color(0xAA000000),
        child: Center(child: child),
      ),
    );
    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));

    unawaited(router.run<bool>(const _OuterFlow()));
    await tester.pumpAndSettle();
    expect(find.text('outer-flow'), findsOneWidget);

    await tester.tap(find.text('open-inner'));
    await tester.pumpAndSettle();

    // The nested flow renders on top; both layers are mounted.
    expect(find.text('inner-flow'), findsOneWidget);
    expect(find.text('outer-flow'), findsOneWidget);
    expect(router.activeFlows.length, 2);

    // Completing the inner flow resumes the outer screen's await.
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    expect(find.text('inner-flow'), findsNothing);
    expect(find.text('received-card-42'), findsOneWidget);
  });
}
