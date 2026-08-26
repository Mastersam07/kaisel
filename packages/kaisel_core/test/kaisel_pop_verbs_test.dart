import 'package:kaisel_core/kaisel_core.dart';
import 'package:test/test.dart';

sealed class _R extends KaiselRoute {
  const _R();
}

final class _Home extends _R {
  const _Home();
}

final class _Cart extends _R {
  const _Cart();
}

final class _Payment extends _R {
  const _Payment();
}

final class _Receipt extends _R {
  const _Receipt();
}

void main() {
  KaiselRouter<_R> routerWith(List<_R> stack) =>
      KaiselRouter<_R>.fromStack(stack);

  group('pushAndPopUntil', () {
    test('keeps the anchor and everything below it', () async {
      final router = routerWith(const [_Home(), _Cart(), _Payment()]);

      await router.pushAndPopUntil(
        const _Receipt(),
        predicate: (route) => route is _Cart,
      );

      expect(router.stack, const [_Home(), _Cart(), _Receipt()]);
    });

    test('anchors on the topmost match', () async {
      final router = routerWith(const [_Home(), _Cart(), _Home(), _Payment()]);

      await router.pushAndPopUntil(
        const _Receipt(),
        predicate: (route) => route is _Home,
      );

      expect(router.stack, const [_Home(), _Cart(), _Home(), _Receipt()]);
    });

    test('replaces the whole stack when nothing matches', () async {
      final router = routerWith(const [_Home(), _Cart()]);

      await router.pushAndPopUntil(
        const _Receipt(),
        predicate: (route) => route is _Payment,
      );

      expect(router.stack, const [_Receipt()]);
    });

    test('runs through guards as one mutation', () async {
      var runs = 0;
      final router = KaiselRouter<_R>.fromStack(
        const [_Home(), _Cart(), _Payment()],
        guards: [
          (current, proposed) {
            runs++;
            return proposed;
          },
        ],
      );

      await router.pushAndPopUntil(
        const _Receipt(),
        predicate: (route) => route is _Home,
      );

      expect(runs, 1);
      expect(router.stack, const [_Home(), _Receipt()]);
    });
  });

  group('popUntil', () {
    test('stops at the topmost match', () async {
      final router = routerWith(const [_Home(), _Cart(), _Payment()]);

      await router.popUntil((route) => route is _Cart);

      expect(router.stack, const [_Home(), _Cart()]);
    });

    test('keeps the root when nothing matches', () async {
      final router = routerWith(const [_Home(), _Cart(), _Payment()]);

      await router.popUntil((route) => route is _Receipt);

      expect(router.stack, const [_Home()]);
    });
  });

  group('history semantics match pop and push', () {
    test('popUntilRoot does not replace the history entry', () async {
      final router = routerWith(const [_Home(), _Cart(), _Payment()]);

      await router.popUntilRoot();

      expect(router.replacesHistoryEntry, isFalse);
    });

    test('pushAndPopUntil adds an entry like push', () async {
      final router = routerWith(const [_Home(), _Cart()]);

      await router.pushAndPopUntil(
        const _Receipt(),
        predicate: (route) => route is _Home,
      );

      expect(router.replacesHistoryEntry, isFalse);
    });

    test('set still replaces, for contrast', () async {
      final router = routerWith(const [_Home(), _Cart()]);

      await router.set(const [_Home()]);

      expect(router.replacesHistoryEntry, isTrue);
    });
  });

  group('popUntilRoot', () {
    test('leaves only the bottom route', () async {
      final router = routerWith(const [_Home(), _Cart(), _Payment()]);

      await router.popUntilRoot();

      expect(router.stack, const [_Home()]);
    });

    test('is a no-op at the root', () async {
      final router = routerWith(const [_Home()]);

      await router.popUntilRoot();

      expect(router.stack, const [_Home()]);
    });
  });
}
