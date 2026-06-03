import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// Fixture: a small module under test.

sealed class _CheckoutRoute extends KaiselRoute {
  const _CheckoutRoute();
}

final class _Cart extends _CheckoutRoute {
  const _Cart();
}

final class _Shipping extends _CheckoutRoute {
  const _Shipping();
}

final class _Confirm extends _CheckoutRoute {
  const _Confirm();
}

class _TestCheckoutModule extends RouteModule<_CheckoutRoute> {
  const _TestCheckoutModule();

  @override
  List<_CheckoutRoute> get initialStack => const [_Cart()];

  @override
  Widget buildPage(BuildContext context, _CheckoutRoute route) =>
      switch (route) {
        _Cart() => const SizedBox(key: ValueKey('cart')),
        _Shipping() => const SizedBox(key: ValueKey('ship')),
        _Confirm() => const SizedBox(key: ValueKey('confirm')),
      };
}

class _ModuleWithDeepInitial extends _TestCheckoutModule {
  const _ModuleWithDeepInitial();

  @override
  List<_CheckoutRoute> get initialStack => const [_Cart(), _Shipping()];
}

// Another type for cross-type rejection tests.
sealed class _OtherRoute extends KaiselRoute {
  const _OtherRoute();
}

final class _OtherRoot extends _OtherRoute {
  const _OtherRoot();
}

void main() {
  group('KaiselModuleConfig', () {
    test('equality is value-based', () {
      final a = KaiselModuleConfig(stack: const [_Cart(), _Shipping()]);
      final b = KaiselModuleConfig(stack: const [_Cart(), _Shipping()]);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('differs when stack differs', () {
      final a = KaiselModuleConfig(stack: const [_Cart()]);
      final b = KaiselModuleConfig(stack: const [_Cart(), _Shipping()]);
      expect(a, isNot(equals(b)));
    });

    test('stack is unmodifiable', () {
      final c = KaiselModuleConfig(stack: [const _Cart()]);
      expect(() => c.stack.add(const _Shipping()), throwsUnsupportedError);
    });

    test('rejects an empty stack', () {
      expect(
        () => KaiselModuleConfig(stack: const []),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('KaiselConfig with nestedState', () {
    test('module config is a KaiselNestedConfig', () {
      // The sealed KaiselNestedConfig type makes "shell + module" a
      // type-level impossibility — at most one nestedState can be
      // assigned. This test pins the type relationship.
      final KaiselNestedConfig moduleState = KaiselModuleConfig(
        stack: const [_Cart()],
      );
      final KaiselNestedConfig shellState = KaiselShellConfig(
        activeBranch: 0,
        activeBranchStack: const [_OtherRoot()],
      );
      expect(moduleState, isA<KaiselModuleConfig>());
      expect(shellState, isA<KaiselShellConfig>());
    });

    test('nestedState supports pattern matching by kind', () {
      final config = KaiselConfig<_OtherRoute>(
        mainStack: const [_OtherRoot()],
        nestedState: KaiselModuleConfig(stack: const [_Cart(), _Shipping()]),
      );
      final result = switch (config.nestedState) {
        KaiselShellConfig() => 'shell',
        KaiselModuleConfig(:final stack) => 'module:${stack.length}',
        null => 'none',
      };
      expect(result, 'module:2');
    });

    test('equality includes nestedState', () {
      final a = KaiselConfig<_OtherRoute>(
        mainStack: const [_OtherRoot()],
        nestedState: KaiselModuleConfig(stack: const [_Cart()]),
      );
      final b = KaiselConfig<_OtherRoute>(
        mainStack: const [_OtherRoot()],
        nestedState: KaiselModuleConfig(stack: const [_Cart()]),
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);

      final c = KaiselConfig<_OtherRoute>(
        mainStack: const [_OtherRoot()],
        nestedState: KaiselModuleConfig(stack: const [_Cart(), _Shipping()]),
      );
      expect(a, isNot(equals(c)));
    });
  });

  group('RouteModule', () {
    test('is const-instantiable', () {
      // ignore: unused_local_variable
      const module = _TestCheckoutModule();
    });

    test('initialStack returns the seed stack', () {
      const module = _TestCheckoutModule();
      expect(module.initialStack, const [_Cart()]);
    });

    test('buildPage pattern-matches over the sealed type', () {
      const module = _TestCheckoutModule();
      // We can't easily check returned widget identity without a
      // BuildContext, but we can check the resolver doesn't throw.
      // Use a fake context via a Builder to get a real one would be
      // overkill; just hit the switch with each case.
      final widgets = <Widget>[
        module.buildPage(_FakeContext(), const _Cart()),
        module.buildPage(_FakeContext(), const _Shipping()),
        module.buildPage(_FakeContext(), const _Confirm()),
      ];
      expect(widgets.length, 3);
    });
  });

  group('KaiselModuleMount widget lifecycle', () {
    testWidgets(
      'creates a router with initialStack and renders the first page',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: KaiselModuleMount<_CheckoutRoute>(
              module: _TestCheckoutModule(),
            ),
          ),
        );

        // The Cart screen is the initial page.
        expect(find.byKey(const ValueKey('cart')), findsOneWidget);
        expect(find.byKey(const ValueKey('ship')), findsNothing);
      },
    );

    testWidgets(
      'a multi-route initialStack lands the module at the top of it',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: KaiselModuleMount<_CheckoutRoute>(
              module: _ModuleWithDeepInitial(),
            ),
          ),
        );

        // The shipping screen (top of initialStack) is shown.
        expect(find.byKey(const ValueKey('ship')), findsOneWidget);
      },
    );

    testWidgets(
      'context.router<R>() inside the module resolves to the typed router',
      (tester) async {
        late KaiselRouter<_CheckoutRoute> capturedRouter;

        await tester.pumpWidget(
          MaterialApp(
            home: KaiselModuleMount<_CheckoutRoute>(
              module: _CaptureRouterModule(
                onBuild: (router) => capturedRouter = router,
              ),
            ),
          ),
        );

        expect(capturedRouter, isA<KaiselRouter<_CheckoutRoute>>());
        expect(capturedRouter.stack, const [_Cart()]);
      },
    );

    testWidgets('unmount disposes the internal router', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: KaiselModuleMount<_CheckoutRoute>(
            module: _TestCheckoutModule(),
          ),
        ),
      );
      // Replace with a different widget — the mount should dispose
      // cleanly. Any disposal error would be caught by tester.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(find.byKey(const ValueKey('cart')), findsNothing);
    });
  });
}

// A tiny fake-context for resolver smoke tests. We only need it to
// pass the type check on buildPage's signature — the resolver doesn't
// dereference it in any of these cases.
class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// Module used to capture the internal router for an assertion in the
// widget test above.
class _CaptureRouterModule extends RouteModule<_CheckoutRoute> {
  const _CaptureRouterModule({required this.onBuild});

  final void Function(KaiselRouter<_CheckoutRoute>) onBuild;

  @override
  List<_CheckoutRoute> get initialStack => const [_Cart()];

  @override
  Widget buildPage(BuildContext context, _CheckoutRoute route) {
    onBuild(context.router<_CheckoutRoute>());
    return const SizedBox();
  }
}
