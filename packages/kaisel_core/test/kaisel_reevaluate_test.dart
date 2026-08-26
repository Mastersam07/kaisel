import 'package:kaisel_core/kaisel_core.dart';
import 'package:test/test.dart';

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

/// An app-lock guard: while locked, a passcode screen sits on top of any
/// protected destination; unlocking drops it again.
KaiselGuard<_R> _lockGuard(bool Function() locked) => (current, proposed) {
  final protected = proposed.any((route) => route is _Vault);
  final hasPasscode = proposed.any((route) => route is _Passcode);
  if (protected && locked() && !hasPasscode)
    return [...proposed, const _Passcode()];
  if (!locked() && hasPasscode) {
    return proposed.where((route) => route is! _Passcode).toList();
  }
  return proposed;
};

void main() {
  test('locking mid-session appends the passcode screen', () async {
    var locked = false;
    final router = KaiselRouter<_R>.fromStack(
      const [_Home(), _Vault()],
      guards: [_lockGuard(() => locked)],
    );

    locked = true;
    await router.reevaluate();

    expect(router.stack, const [_Home(), _Vault(), _Passcode()]);
  });

  test('unlocking drops it again, from the same guard', () async {
    var locked = true;
    final router = KaiselRouter<_R>.fromStack(
      const [_Home(), _Vault()],
      guards: [_lockGuard(() => locked)],
    );
    await router.reevaluate();
    expect(router.stack.last, const _Passcode());

    locked = false;
    await router.reevaluate();

    expect(router.stack, const [_Home(), _Vault()]);
  });

  test('is idempotent — repeat calls commit nothing', () async {
    const locked = true;
    var notifications = 0;
    final router = KaiselRouter<_R>.fromStack(
      const [_Home(), _Vault()],
      guards: [_lockGuard(() => locked)],
    )..addListener(() => notifications++);

    await router.reevaluate();
    final afterFirst = notifications;
    await router.reevaluate();
    await router.reevaluate();

    expect(router.stack, const [_Home(), _Vault(), _Passcode()]);
    expect(notifications, afterFirst);
  });

  test('does nothing when no guard wants a change', () async {
    final router = KaiselRouter<_R>.fromStack(const [_Home(), _Vault()]);

    await router.reevaluate();

    expect(router.stack, const [_Home(), _Vault()]);
  });

  test('serializes with an in-flight navigation', () async {
    const locked = true;
    final router = KaiselRouter<_R>.fromStack(
      const [_Home()],
      guards: [_lockGuard(() => locked)],
    );

    final push = router.push(const _Vault());
    final reevaluate = router.reevaluate();
    await Future.wait([push, reevaluate]);

    expect(router.stack, const [_Home(), _Vault(), _Passcode()]);
  });
}
