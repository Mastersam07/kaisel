import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';
import 'package:kaisel/src/kaisel_browser_history.dart';
import 'package:kaisel/src/kaisel_browser_history_stub.dart' as stub;

sealed class _R extends KaiselRoute {
  const _R();
}

final class _A extends _R {
  const _A();
}

final class _B extends _R {
  const _B();
}

final class _C extends _R {
  const _C();
}

class _Codec implements KaiselStackCodec<_R> {
  const _Codec();
  @override
  Uri encode(List<_R> stack) => switch (stack.last) {
    _A() => Uri(path: '/a'),
    _B() => Uri(path: '/b'),
    _C() => Uri(path: '/c'),
  };
  @override
  List<_R>? decode(Uri uri) => switch (uri.pathSegments) {
    ['b'] => const [_A(), _B()],
    ['c'] => const [_A(), _B(), _C()],
    _ => const [_A()],
  };
}

class _FakeHistory implements KaiselBrowserHistory {
  _FakeHistory({this.isWeb = true, this.depth = 0});
  @override
  bool isWeb;
  @override
  int depth;
  final gos = <int>[];
  @override
  void go(int delta) => gos.add(delta);
}

void main() {
  // Build a config whose stack is [_A, _B, _C], returning a context under it.
  Future<(KaiselRouterConfig<_R>, BuildContext)> pumpDeepStack(
    WidgetTester tester,
  ) async {
    final config = KaiselRouterConfig<_R>(
      initial: const _A(),
      builder: (_, route) =>
          Text('${route.runtimeType}', textDirection: TextDirection.ltr),
      codec: const StackToConfigCodec<_R>(_Codec()),
      fallback: const [_A()],
    );
    addTearDown(config.router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: config));
    await tester.pumpAndSettle();
    await config.router.set(const [_A(), _B(), _C()]);
    await tester.pumpAndSettle();
    expect(config.router.stack, const [_A(), _B(), _C()]);
    return (config, tester.element(find.text('_C')));
  }

  testWidgets('back() on web moves the history pointer, not the stack', (
    tester,
  ) async {
    final fake = _FakeHistory(isWeb: true, depth: 2);
    addTearDown(KaiselBrowserHistory.debugOverride(fake));

    final (config, context) = await pumpDeepStack(tester);

    final moved = await context.back();
    await tester.pumpAndSettle();

    expect(moved, isTrue);
    expect(fake.gos, [-1]);
    // The stack is unchanged here: the real restore arrives via the browser's
    // popstate (inbound), which the fake doesn't simulate.
    expect(config.router.stack, const [_A(), _B(), _C()]);
  });

  testWidgets('historyGo(-2) issues a single go(-2) on web', (tester) async {
    final fake = _FakeHistory(isWeb: true, depth: 5);
    addTearDown(KaiselBrowserHistory.debugOverride(fake));

    final (config, context) = await pumpDeepStack(tester);

    expect(await context.historyGo(-2), isTrue);
    expect(fake.gos, [-2]);
    expect(config.router.stack, const [_A(), _B(), _C()]);
  });

  testWidgets('falls back to pop off the web', (tester) async {
    final fake = _FakeHistory(isWeb: false);
    addTearDown(KaiselBrowserHistory.debugOverride(fake));

    final (config, context) = await pumpDeepStack(tester);

    expect(await context.back(), isTrue);
    await tester.pumpAndSettle();

    expect(fake.gos, isEmpty);
    expect(config.router.stack, const [_A(), _B()]);
  });

  testWidgets('falls back to pop at a cold deep link (depth 0)', (
    tester,
  ) async {
    final fake = _FakeHistory(isWeb: true, depth: 0);
    addTearDown(KaiselBrowserHistory.debugOverride(fake));

    final (config, context) = await pumpDeepStack(tester);

    expect(await context.back(), isTrue);
    await tester.pumpAndSettle();

    expect(fake.gos, isEmpty);
    expect(config.router.stack, const [_A(), _B()]);
  });

  testWidgets('historyGo(-2) fallback pops twice, clamped at root', (
    tester,
  ) async {
    final fake = _FakeHistory(isWeb: false);
    addTearDown(KaiselBrowserHistory.debugOverride(fake));

    final (config, context) = await pumpDeepStack(tester);

    expect(await context.historyGo(-2), isTrue);
    await tester.pumpAndSettle();

    expect(fake.gos, isEmpty);
    expect(config.router.stack, const [_A()]);
  });

  testWidgets('historyGo(1) goes forward on web', (tester) async {
    final fake = _FakeHistory(isWeb: true, depth: 0);
    addTearDown(KaiselBrowserHistory.debugOverride(fake));

    final (config, context) = await pumpDeepStack(tester);

    // Forward needs no depth check — the browser ignores it past the end.
    expect(await context.historyGo(1), isTrue);
    expect(fake.gos, [1]);
    expect(config.router.stack, const [_A(), _B(), _C()]);
  });

  test('the non-web stub is inert', () {
    final history = stub.createBrowserHistory();
    expect(history.isWeb, isFalse);
    expect(history.depth, 0);
    expect(() => history.go(-1), returnsNormally);
  });
}
