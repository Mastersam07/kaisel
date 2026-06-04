import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

sealed class _R extends KaiselRoute {
  const _R();
}

final class _A extends _R {
  const _A();
}

final class _B extends _R {
  const _B();
}

void main() {
  testWidgets('KaiselListenableBuilder rebuilds when the router changes', (
    tester,
  ) async {
    final router = KaiselRouter<_R>(initial: const _A());
    addTearDown(router.dispose);
    var builds = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: KaiselListenableBuilder<_R>(
          router: router,
          builder: (context, _) {
            builds++;
            return Text('${router.depth}');
          },
        ),
      ),
    );

    expect(builds, 1);
    expect(find.text('1'), findsOneWidget);

    await router.push(const _B());
    await tester.pump();

    expect(builds, 2);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('a disposed KaiselListenableBuilder stops rebuilding', (
    tester,
  ) async {
    final router = KaiselRouter<_R>(initial: const _A());
    addTearDown(router.dispose);
    var builds = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: KaiselListenableBuilder<_R>(
          router: router,
          builder: (context, _) {
            builds++;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(builds, 1);

    // Tear the builder out of the tree, then mutate the router.
    await tester.pumpWidget(const SizedBox());
    await router.push(const _B());
    await tester.pump();

    expect(builds, 1, reason: 'a disposed builder must not rebuild');
  });

  test(
    'asListenable forwards registration and is stable across calls',
    () async {
      final router = KaiselRouter<_R>(initial: const _A());
      addTearDown(router.dispose);

      // Two adapters over the same router compare equal, so ListenableBuilder
      // does not churn its subscription across rebuilds.
      expect(router.asListenable(), equals(router.asListenable()));

      var notifications = 0;
      void listener() => notifications++;
      final listenable = router.asListenable()..addListener(listener);

      await router.push(const _B());
      expect(notifications, 1);

      listenable.removeListener(listener);
      await router.push(const _A());
      expect(notifications, 1, reason: 'a removed listener must not fire');
    },
  );
}
