import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

sealed class _R extends KaiselRoute {
  const _R();
}

final class _List extends _R {
  const _List();
}

final class _Detail extends _R {
  const _Detail(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}

void main() {
  testWidgets('KaiselRouterConfig forwards onTransition; swaps carry values', (
    tester,
  ) async {
    final calls = <(List<_R>, List<_R>)>[];
    final config = KaiselRouterConfig<_R>(
      initial: const _List(),
      builder: (context, route) => const Scaffold(body: SizedBox.shrink()),
      onTransition: (from, to) => calls.add((from, to)),
    );
    addTearDown(config.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: config));

    await config.router.push(const _Detail('a'));
    await config.router.replaceTop(const _Detail('b'));
    await tester.pumpAndSettle();

    final (from, to) = calls.last;
    expect(from, [const _List(), const _Detail('a')]);
    expect(to, [const _List(), const _Detail('b')]);
  });

  testWidgets('fires for a system-back pop (Navigator-driven removal)', (
    tester,
  ) async {
    final calls = <(List<_R>, List<_R>)>[];
    final config = KaiselRouterConfig<_R>(
      initial: const _List(),
      builder: (context, route) => const Scaffold(body: SizedBox.shrink()),
      onTransition: (from, to) => calls.add((from, to)),
    );
    addTearDown(config.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: config));

    await config.router.push(const _Detail('a'));
    await tester.pumpAndSettle();
    calls.clear();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single.$1, [const _List(), const _Detail('a')]);
    expect(calls.single.$2, [const _List()]);
  });
}
