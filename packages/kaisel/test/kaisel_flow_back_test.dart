import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// Back/pop order with flows rendered as routes (Option C):
// system back should pop a flow's inner screens first, then dismiss the flow,
// then unwind the main stack.

sealed class _App extends KaiselRoute {
  const _App();
}

final class _Home extends _App {
  const _Home();
}

final class _Flow extends _App implements KaiselModalRoute<String> {
  const _Flow();
}

final class _FlowStep extends _App {
  const _FlowStep();
}

KaiselRouterDelegate<_App> _buildDelegate(KaiselRouter<_App> router) =>
    KaiselRouterDelegate<_App>(
      router: router,
      builder: (context, route) => switch (route) {
        _Home() => const Scaffold(body: Center(child: Text('home'))),
        _Flow() => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => context.router<_App>().push(const _FlowStep()),
              child: const Text('go-deeper'),
            ),
          ),
        ),
        _FlowStep() => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('flow-step'),
                Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const AlertDialog(content: Text('sheet')),
                    ),
                    child: const Text('show-dialog'),
                  ),
                ),
              ],
            ),
          ),
        ),
      },
      modalBuilder: (context, route, flowContent) => flowContent,
    );

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('back dismisses a flow at its root with null', (tester) async {
    final router = KaiselRouter<_App>(initial: const _Home());
    final delegate = _buildDelegate(router);

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    final result = router.run<String>(const _Flow());
    await tester.pumpAndSettle();
    expect(router.hasActiveFlow, isTrue);
    expect(find.text('go-deeper'), findsOneWidget);

    await _back(tester);

    expect(await result, isNull);
    expect(router.hasActiveFlow, isFalse);
    expect(find.text('home'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });

  testWidgets('back pops a flow inner screen before dismissing the flow', (
    tester,
  ) async {
    final router = KaiselRouter<_App>(initial: const _Home());
    final delegate = _buildDelegate(router);

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    final result = router.run<String>(const _Flow());
    await tester.pumpAndSettle();

    // Go one screen deep inside the flow.
    await tester.tap(find.text('go-deeper'));
    await tester.pumpAndSettle();
    expect(find.text('flow-step'), findsOneWidget);

    // First back pops the inner screen; the flow stays open.
    await _back(tester);
    expect(router.hasActiveFlow, isTrue);
    expect(find.text('flow-step'), findsNothing);
    expect(find.text('go-deeper'), findsOneWidget);

    // Second back dismisses the flow.
    await _back(tester);
    expect(await result, isNull);
    expect(router.hasActiveFlow, isFalse);
    expect(find.text('home'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });

  testWidgets('back unwinds dialog → flow inner screen → flow → main', (
    tester,
  ) async {
    final router = KaiselRouter<_App>(initial: const _Home());
    final delegate = _buildDelegate(router);

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    final result = router.run<String>(const _Flow());
    await tester.pumpAndSettle();

    await tester.tap(find.text('go-deeper'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('show-dialog'));
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);

    // 1) dialog closes
    await _back(tester);
    expect(find.text('sheet'), findsNothing);
    expect(find.text('flow-step'), findsOneWidget);
    expect(router.hasActiveFlow, isTrue);

    // 2) flow inner screen pops
    await _back(tester);
    expect(find.text('flow-step'), findsNothing);
    expect(find.text('go-deeper'), findsOneWidget);
    expect(router.hasActiveFlow, isTrue);

    // 3) flow dismisses
    await _back(tester);
    expect(await result, isNull);
    expect(router.hasActiveFlow, isFalse);
    expect(find.text('home'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });

  testWidgets('a raw Navigator.pop on a flow route dismisses it with null', (
    tester,
  ) async {
    final router = KaiselRouter<_App>(initial: const _Home());
    final delegate = _buildDelegate(router);

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    final result = router.run<String>(const _Flow());
    await tester.pumpAndSettle();
    expect(router.hasActiveFlow, isTrue);

    // Pop the main navigator imperatively — removes the flow page.
    final navState = delegate.navigatorKey.currentState;
    expect(navState, isNotNull);
    navState?.pop();
    await tester.pumpAndSettle();

    expect(await result, isNull);
    expect(router.hasActiveFlow, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });
}
