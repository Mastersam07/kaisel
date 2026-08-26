import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

sealed class _R extends KaiselRoute {
  const _R();
}

final class _Home extends _R {
  const _Home();
}

final class _Vault extends _R {
  const _Vault();
}

final class _Passcode extends _R {
  const _Passcode();
}

KaiselGuard<_R> _lockGuard(ValueListenable<bool> locked) =>
    (current, proposed) {
      final protected = proposed.any((route) => route is _Vault);
      final shown = proposed.any((route) => route is _Passcode);
      if (protected && locked.value && !shown) {
        return [...proposed, const _Passcode()];
      }
      if (!locked.value && shown) {
        return proposed.where((route) => route is! _Passcode).toList();
      }
      return proposed;
    };

void main() {
  testWidgets('a lock firing on a timer re-runs guards on the idle stack', (
    tester,
  ) async {
    final locked = ValueNotifier<bool>(false);
    addTearDown(locked.dispose);
    final config = KaiselRouterConfig<_R>(
      initial: const _Home(),
      guards: [_lockGuard(locked)],
      reevaluateOn: locked,
      builder: (context, route) => switch (route) {
        _Home() => const Scaffold(body: Text('home')),
        _Vault() => const Scaffold(body: Text('vault')),
        _Passcode() => const Scaffold(body: Text('passcode')),
      },
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: config));
    await config.router.push(const _Vault());
    await tester.pumpAndSettle();
    expect(find.text('vault'), findsOneWidget);

    locked.value = true;
    await tester.pumpAndSettle();

    expect(config.router.stack, const [_Home(), _Vault(), _Passcode()]);
    expect(find.text('passcode'), findsOneWidget);
  });

  testWidgets('unlocking removes it through the same guard', (tester) async {
    final locked = ValueNotifier<bool>(true);
    addTearDown(locked.dispose);
    final config = KaiselRouterConfig<_R>(
      initial: const _Home(),
      guards: [_lockGuard(locked)],
      reevaluateOn: locked,
      builder: (context, route) => switch (route) {
        _Home() => const Scaffold(body: Text('home')),
        _Vault() => const Scaffold(body: Text('vault')),
        _Passcode() => const Scaffold(body: Text('passcode')),
      },
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: config));
    await config.router.push(const _Vault());
    await tester.pumpAndSettle();
    expect(config.router.stack.last, const _Passcode());

    locked.value = false;
    await tester.pumpAndSettle();

    expect(config.router.stack, const [_Home(), _Vault()]);
  });

  testWidgets('the subscription is dropped when the delegate is disposed', (
    tester,
  ) async {
    final locked = ValueNotifier<bool>(false);
    addTearDown(locked.dispose);
    final router = KaiselRouter<_R>(initial: const _Home());
    final delegate = KaiselRouterDelegate<_R>(
      router: router,
      reevaluateOn: locked,
      builder: (context, route) => const Scaffold(body: Text('home')),
    );
    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));

    delegate.dispose();
    locked.value = true;
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
