import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

sealed class _R extends KaiselRoute {
  const _R();
}

final class _Home extends _R {
  const _Home();
}

final class _Login extends _R {
  const _Login();
}

final class _Checkout extends _R implements KaiselModalRoute<bool> {
  const _Checkout();
}

final class _Payment extends _R {
  const _Payment();
}

void main() {
  testWidgets('signing out mid flow closes the flow and shows Login', (
    tester,
  ) async {
    final signedIn = ValueNotifier<bool>(true);
    addTearDown(signedIn.dispose);
    final config = KaiselRouterConfig<_R>(
      initial: const _Home(),
      guards: [
        (current, proposed) => signedIn.value ? proposed : const [_Login()],
      ],
      reevaluateOn: signedIn,
      builder: (context, route) => switch (route) {
        _Home() => const Scaffold(body: Text('home')),
        _Login() => const Scaffold(body: Text('login')),
        _Checkout() => const Scaffold(body: Text('checkout')),
        _Payment() => const Scaffold(body: Text('payment')),
      },
      modalBuilder: (context, route, flowContent) => flowContent,
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: config));

    final result = config.router.run(const _Checkout());
    await tester.pumpAndSettle();
    await config.router.activeFlows.last.router.push(const _Payment());
    await tester.pumpAndSettle();
    expect(find.text('payment'), findsOneWidget);

    signedIn.value = false;
    await tester.pumpAndSettle();

    expect(await result, isNull);
    expect(config.router.hasActiveFlow, isFalse);
    expect(find.text('payment'), findsNothing);
    expect(find.text('checkout'), findsNothing);
    expect(find.text('login'), findsOneWidget);
  });
}
