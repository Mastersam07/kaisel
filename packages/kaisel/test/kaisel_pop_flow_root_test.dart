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

// The reporter's case: one screen usable as a pushed page and as a flow root.
final class _Editor extends _R implements KaiselModalRoute<String> {
  const _Editor();
}

final class _Step2 extends _R {
  const _Step2();
}

final class _Inner extends _R implements KaiselModalRoute<String> {
  const _Inner();
}

Widget _screen(String label, VoidCallback onBack) => Scaffold(
  body: Center(
    child: ElevatedButton(onPressed: onBack, child: Text(label)),
  ),
);

KaiselRouterDelegate<_R> _delegateFor(KaiselRouter<_R> router) =>
    KaiselRouterDelegate<_R>(
      router: router,
      modalBuilder: (context, route, child) => Center(child: child),
      builder: (context, route) => switch (route) {
        _Home() => const Scaffold(body: Text('home')),
        _Editor() => Builder(
          builder: (context) => _screen('editor-back', () {
            context.pop('saved');
          }),
        ),
        _Step2() => Builder(
          builder: (context) => _screen('step2-back', context.pop),
        ),
        _Inner() => Builder(
          builder: (context) => _screen('inner-back', () {
            context.pop('inner-done');
          }),
        ),
      },
    );

void main() {
  testWidgets('pop on a flow root completes the flow with the result', (
    tester,
  ) async {
    final router = KaiselRouter<_R>(initial: const _Home());
    String? result;
    await tester.pumpWidget(
      MaterialApp.router(routerDelegate: _delegateFor(router)),
    );

    unawaited(router.run<String>(const _Editor()).then((v) => result = v));
    await tester.pumpAndSettle();

    await tester.tap(find.text('editor-back'));
    await tester.pumpAndSettle();

    expect(router.hasActiveFlow, isFalse);
    expect(result, 'saved');
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('the same screen still pops normally when pushed as a page', (
    tester,
  ) async {
    final router = KaiselRouter<_R>(initial: const _Home());
    String? result;
    await tester.pumpWidget(
      MaterialApp.router(routerDelegate: _delegateFor(router)),
    );

    unawaited(
      router.pushForResult<String>(const _Editor()).then((v) => result = v),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('editor-back'));
    await tester.pumpAndSettle();

    expect(router.stack, const [_Home()]);
    expect(result, 'saved');
  });

  testWidgets('inside a flow sub-stack it pops the step, not the flow', (
    tester,
  ) async {
    final router = KaiselRouter<_R>(initial: const _Home());
    await tester.pumpWidget(
      MaterialApp.router(routerDelegate: _delegateFor(router)),
    );

    unawaited(router.run<String>(const _Editor()));
    await tester.pumpAndSettle();
    final flowRouter = router.activeFlows.first.router;
    await flowRouter.push(const _Step2());
    await tester.pumpAndSettle();

    await tester.tap(find.text('step2-back'));
    await tester.pumpAndSettle();

    expect(router.hasActiveFlow, isTrue);
    expect(flowRouter.stack, const [_Editor()]);
    expect(find.text('editor-back'), findsOneWidget);
  });

  testWidgets('a nested flow root completes the inner flow only', (
    tester,
  ) async {
    final router = KaiselRouter<_R>(initial: const _Home());
    String? outer;
    String? inner;
    await tester.pumpWidget(
      MaterialApp.router(routerDelegate: _delegateFor(router)),
    );

    unawaited(router.run<String>(const _Editor()).then((v) => outer = v));
    await tester.pumpAndSettle();
    unawaited(
      router.activeFlows.first.router
          .run<String>(const _Inner())
          .then((v) => inner = v),
    );
    await tester.pumpAndSettle();
    expect(router.activeFlows.length, 2);

    await tester.tap(find.text('inner-back'));
    await tester.pumpAndSettle();

    expect(inner, 'inner-done');
    expect(outer, isNull);
    expect(router.activeFlows.length, 1);
  });

  testWidgets('at the root of the main stack it still reports false', (
    tester,
  ) async {
    final router = KaiselRouter<_R>(initial: const _Home());
    late BuildContext homeContext;
    final delegate = KaiselRouterDelegate<_R>(
      router: router,
      builder: (context, route) => Builder(
        builder: (context) {
          homeContext = context;
          return const Scaffold(body: Text('home'));
        },
      ),
    );
    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));

    expect(await homeContext.pop(), isFalse);
    expect(router.stack, const [_Home()]);
  });
}
