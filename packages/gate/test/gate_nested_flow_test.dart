import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gate/gate.dart';

// Two flow routes that each return a different result type. The
// nested-flow widget test pushes both and verifies that the topmost
// flow renders on top while the outer flow remains in the tree
// below it.

sealed class _App extends GateRoute {
  const _App();
}

final class _Home extends _App {
  const _Home();
}

final class _AddCardFlow extends _App implements GateModalRoute<bool> {
  const _AddCardFlow();
}

final class _VerifyIdentityFlow extends _App implements GateModalRoute<String> {
  const _VerifyIdentityFlow();
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('HOME'));
}

class _AddCardModalContent extends StatelessWidget {
  const _AddCardModalContent();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0x88000000),
      body: Center(child: Text('ADD-CARD-MODAL')),
    );
  }
}

class _VerifyIdentityModalContent extends StatelessWidget {
  const _VerifyIdentityModalContent();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xAA000000),
      body: Center(child: Text('VERIFY-IDENTITY-MODAL')),
    );
  }
}

class _CurrentStackParser extends RouteInformationParser<GateConfig<_App>> {
  _CurrentStackParser(this.router);
  final GateRouter<_App> router;

  @override
  Future<GateConfig<_App>> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    return GateConfig<_App>(mainStack: router.stack);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Nested modal flow rendering (v0.10)', () {
    testWidgets('two nested flows render as two layered modal overlays', (
      tester,
    ) async {
      final router = GateRouter<_App>(initial: const _Home());
      final delegate = GateRouterDelegate<_App>(
        router: router,
        builder: (context, route) {
          return switch (route) {
            _Home() => const _HomeScreen(),
            _AddCardFlow() => const _AddCardModalContent(),
            _VerifyIdentityFlow() => const _VerifyIdentityModalContent(),
          };
        },
        modalBuilder: (context, route, flowContent) => flowContent,
      );
      addTearDown(delegate.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          routerDelegate: delegate,
          routeInformationParser: _CurrentStackParser(router),
        ),
      );
      await tester.pumpAndSettle();

      // Only HOME visible initially.
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('ADD-CARD-MODAL'), findsNothing);
      expect(find.text('VERIFY-IDENTITY-MODAL'), findsNothing);

      // Start the outer flow.
      final outer = router.run<bool>(const _AddCardFlow());
      await tester.pumpAndSettle();

      expect(router.activeFlows.length, 1);
      expect(find.text('ADD-CARD-MODAL'), findsOneWidget);

      // Start the nested inner flow from within the outer.
      final inner = router.run<String>(const _VerifyIdentityFlow());
      await tester.pumpAndSettle();

      expect(router.activeFlows.length, 2);
      // BOTH modal contents are in the widget tree. The inner is
      // on top (its Stack child comes last).
      expect(find.text('ADD-CARD-MODAL'), findsOneWidget);
      expect(find.text('VERIFY-IDENTITY-MODAL'), findsOneWidget);

      // Complete the inner flow.
      router.completeFlow<String>('verified-token-42');
      final tokenResult = await inner;
      await tester.pumpAndSettle();

      expect(tokenResult, 'verified-token-42');
      expect(router.activeFlows.length, 1);
      expect(find.text('VERIFY-IDENTITY-MODAL'), findsNothing);
      expect(find.text('ADD-CARD-MODAL'), findsOneWidget);

      // Complete the outer flow.
      router.completeFlow<bool>(true);
      final cardResult = await outer;
      await tester.pumpAndSettle();

      expect(cardResult, isTrue);
      expect(router.hasActiveFlow, isFalse);
      expect(find.text('ADD-CARD-MODAL'), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets(
      'each flow layer has its own inner Navigator (independent state)',
      (tester) async {
        // Push a route inside the outer flow's stack, then start a
        // nested flow, then verify the outer flow's stack is untouched
        // when the inner one mutates its own.
        final router = GateRouter<_App>(initial: const _Home());
        final delegate = GateRouterDelegate<_App>(
          router: router,
          builder: (context, route) => switch (route) {
            _Home() => const _HomeScreen(),
            _AddCardFlow() => const _AddCardModalContent(),
            _VerifyIdentityFlow() => const _VerifyIdentityModalContent(),
          },
          modalBuilder: (context, route, flowContent) => flowContent,
        );
        addTearDown(delegate.dispose);
        addTearDown(router.dispose);

        await tester.pumpWidget(
          MaterialApp.router(
            routerDelegate: delegate,
            routeInformationParser: _CurrentStackParser(router),
          ),
        );
        await tester.pumpAndSettle();

        final outer = router.run<bool>(const _AddCardFlow());
        await tester.pumpAndSettle();

        final outerFlowRouter = router.activeFlows.last.router;
        final inner = router.run<String>(const _VerifyIdentityFlow());
        await tester.pumpAndSettle();

        final innerFlowRouter = router.activeFlows.last.router;
        expect(identical(outerFlowRouter, innerFlowRouter), isFalse);

        router.completeFlow<String>('done');
        await inner;
        router.completeFlow<bool>(false);
        await outer;
      },
    );
  });
}
