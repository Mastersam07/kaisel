import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';
import 'package:kaisel/src/kaisel_adaptive.dart' show KaiselAdaptiveKey;

// Coverage for a few internal/defensive code paths that the feature tests
// don't reach directly.

sealed class _R extends KaiselRoute {
  const _R();
}

final class _A extends _R {
  const _A();
}

sealed class _App extends KaiselRoute {
  const _App();
}

final class _Home extends _App {
  const _Home();
}

final class _Flow extends _App implements KaiselModalRoute<void> {
  const _Flow();
}

final class _FlowStep extends _App {
  const _FlowStep();
}

sealed class _Co extends KaiselRoute {
  const _Co();
}

final class _Cart extends _Co {
  const _Cart();
}

final class _Ship extends _Co {
  const _Ship();
}

class _CoModule extends RouteModule<_Co> {
  const _CoModule();

  @override
  List<_Co> get initialStack => const [_Cart()];

  @override
  Widget buildPage(BuildContext context, _Co route) => switch (route) {
    _Cart() => const Scaffold(body: Center(child: Text('cart'))),
    _Ship() => const Scaffold(body: Center(child: Text('ship'))),
  };
}

sealed class _M extends KaiselRoute {
  const _M();
}

final class _ModuleHost extends _M {
  const _ModuleHost();
}

void main() {
  test('KaiselAdaptiveKey: equality by stableId, hashCode, toString', () {
    const a = KaiselAdaptiveKey(1, 2);
    const sameStable = KaiselAdaptiveKey(1, 9);
    const otherStable = KaiselAdaptiveKey(7, 2);

    expect(a, sameStable); // == ignores popId
    expect(a.hashCode, sameStable.hashCode); // hashCode derives from stableId
    expect(a == otherStable, isFalse);
    expect(a.toString(), 'KaiselAdaptiveKey(stable: 1, pop: 2)');
  });

  testWidgets('an adaptive page that absorbs more than the stack asserts', (
    tester,
  ) async {
    final router = KaiselRouter<_R>(initial: const _A());
    final delegate = KaiselRouterDelegate<_R>.adaptive(
      router: router,
      builder: (context, route, stack) =>
          const KaiselAbsorbingPage(widget: Scaffold(), absorbing: 5),
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    expect(tester.takeException(), isA<AssertionError>());

    delegate.dispose();
    router.dispose();
  });

  testWidgets('a flow inner navigator syncs its router when a page is popped '
      'imperatively', (tester) async {
    final router = KaiselRouter<_App>(initial: const _Home());
    final delegate = KaiselRouterDelegate<_App>(
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
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('nav-pop'),
              ),
            ),
          ),
        ),
      },
      modalBuilder: (context, route, flowContent) => flowContent,
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    unawaited(router.run<void>(const _Flow()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('go-deeper'));
    await tester.pumpAndSettle();
    expect(find.text('nav-pop'), findsOneWidget);

    await tester.tap(find.text('nav-pop'));
    await tester.pumpAndSettle();
    expect(find.text('nav-pop'), findsNothing);
    expect(find.text('go-deeper'), findsOneWidget);
    expect(router.hasActiveFlow, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });

  testWidgets('a mounted module handle is matched by its config type on a '
      'nested restore', (tester) async {
    final router = KaiselRouter<_M>(initial: const _ModuleHost());
    final delegate = KaiselRouterDelegate<_M>(
      router: router,
      builder: (context, route) => switch (route) {
        _ModuleHost() => const KaiselModuleMount<_Co>(module: _CoModule()),
      },
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    await tester.pumpAndSettle();
    expect(find.text('cart'), findsOneWidget);

    await delegate.setNewRoutePath(
      KaiselConfig<_M>(
        mainStack: const [_ModuleHost()],
        nestedState: KaiselModuleConfig(stack: const [_Cart(), _Ship()]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ship'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });
}
