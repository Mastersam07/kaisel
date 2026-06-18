import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// Under Option C a flow is a route on the main navigator, so the app's shared
// observer sees the flow open and close — the boundary a separate-navigator
// flow hides today. Internal flow screens stay on the inner navigator.

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

class _RecordingObserver extends NavigatorObserver {
  final List<String> pushed = <String>[];
  final List<String> popped = <String>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name case final name?) pushed.add(name);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name case final name?) popped.add(name);
  }
}

void main() {
  // Returns a fresh observer per navigator (a NavigatorObserver belongs to one
  // Navigator), capturing each so a test can inspect the main one (the first
  // created) separately from a flow's inner-navigator observer.
  ({KaiselRouterDelegate<_App> delegate, List<_RecordingObserver> created})
  build(KaiselRouter<_App> router) {
    final created = <_RecordingObserver>[];
    final delegate = KaiselRouterDelegate<_App>(
      router: router,
      observers: () {
        final observer = _RecordingObserver();
        created.add(observer);
        return [observer];
      },
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
        _FlowStep() => const Scaffold(body: Center(child: Text('flow-step'))),
      },
      modalBuilder: (context, route, flowContent) => flowContent,
    );
    return (delegate: delegate, created: created);
  }

  testWidgets('the main navigator observer sees a flow open and close', (
    tester,
  ) async {
    final router = KaiselRouter<_App>(initial: const _Home());
    final (:delegate, :created) = build(router);

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    final mainObserver = created.first; // built for the main navigator

    final result = router.run<String>(const _Flow());
    await tester.pumpAndSettle();
    expect(mainObserver.pushed, contains('_Flow'));

    router.completeFlow<String>('done');
    await result;
    await tester.pumpAndSettle();
    expect(mainObserver.popped, contains('_Flow'));

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });

  testWidgets('a flow inner screen is not seen by the main observer', (
    tester,
  ) async {
    final router = KaiselRouter<_App>(initial: const _Home());
    final (:delegate, :created) = build(router);

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    final mainObserver = created.first;

    final result = router.run<String>(const _Flow());
    await tester.pumpAndSettle();
    await tester.tap(find.text('go-deeper'));
    await tester.pumpAndSettle();
    expect(find.text('flow-step'), findsOneWidget);

    // The flow boundary is on the main navigator; the inner screen is not.
    expect(mainObserver.pushed, contains('_Flow'));
    expect(mainObserver.pushed, isNot(contains('_FlowStep')));

    router.dismissFlow();
    await result;
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });
}
