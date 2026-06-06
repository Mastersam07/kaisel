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

  testWidgets(
    'KaiselListenableBuilder rewires to the new router when the router prop '
    'changes',
    (tester) async {
      final routerA = KaiselRouter<_R>(initial: const _A());
      final routerB = KaiselRouter<_R>(initial: const _A());
      addTearDown(routerA.dispose);
      addTearDown(routerB.dispose);

      var builds = 0;

      Widget buildWith(KaiselRouter<_R> router) => Directionality(
        textDirection: TextDirection.ltr,
        child: KaiselListenableBuilder<_R>(
          // Same widget position across both pumps so the State is reused
          // and didUpdateWidget runs instead of a fresh initState.
          key: const ValueKey('builder'),
          router: router,
          builder: (context, _) {
            builds++;
            return Text('depth ${router.depth}');
          },
        ),
      );

      await routerA.push(const _B());
      await tester.pumpWidget(buildWith(routerA));
      expect(find.text('depth 2'), findsOneWidget);

      await tester.pumpWidget(buildWith(routerB));
      expect(
        find.text('depth 1'),
        findsOneWidget,
        reason: 'output must reflect the new router B',
      );

      final buildsBeforeB = builds;
      await routerB.push(const _B());
      await tester.pump();
      expect(
        builds,
        greaterThan(buildsBeforeB),
        reason: 'a change to the new router must trigger a rebuild',
      );
      expect(find.text('depth 2'), findsOneWidget);

      // A change to the OLD router A must NOT rebuild the widget: the old
      // listener was removed in didUpdateWidget.
      final buildsBeforeA = builds;
      await routerA.push(const _A());
      await tester.pump();
      expect(
        builds,
        buildsBeforeA,
        reason: 'a change to the old router must not trigger a rebuild',
      );
      expect(
        find.text('depth 2'),
        findsOneWidget,
        reason: 'output must still reflect router B, not A',
      );
    },
  );

  test('asListenable equality reflects the underlying router', () async {
    final routerA = KaiselRouter<_R>(initial: const _A());
    final routerB = KaiselRouter<_R>(initial: const _A());
    addTearDown(routerA.dispose);
    addTearDown(routerB.dispose);

    final fromA1 = routerA.asListenable();
    final fromA2 = routerA.asListenable();
    final fromB = routerB.asListenable();

    // Same router: equal and equal hashCode, so ListenableBuilder treats
    // repeated asListenable() calls as the same listenable and avoids churn.
    expect(fromA1, equals(fromA2));
    expect(fromA1.hashCode, equals(fromA2.hashCode));

    expect(fromA1, isNot(equals(fromB)));
  });
}
