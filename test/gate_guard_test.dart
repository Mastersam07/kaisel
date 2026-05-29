import 'package:flutter_test/flutter_test.dart';
import 'package:gate/gate.dart';

sealed class _R extends GateRoute {
  const _R();
}

final class _Home extends _R {
  const _Home();
}

final class _Protected extends _R {
  const _Protected();
}

final class _Login extends _R {
  const _Login();
}

void main() {
  group('GateGuard pipeline', () {
    test('a permissive guard does not interfere', () async {
      final r = GateRouter<_R>(
        initial: const _Home(),
        guards: [(current, proposed) => proposed],
      );
      await r.push(const _Protected());
      expect(r.stack, [const _Home(), const _Protected()]);
    });

    test('a redirecting guard rewrites the proposed stack', () async {
      var loggedIn = false;
      final r = GateRouter<_R>(
        initial: const _Home(),
        guards: [
          (current, proposed) {
            if (proposed.any((r) => r is _Protected) && !loggedIn) {
              return const [_Login()];
            }
            return proposed;
          },
        ],
      );

      await r.push(const _Protected());
      expect(r.stack, [const _Login()]);

      // Once "logged in", the same push reaches its destination.
      loggedIn = true;
      await r.set(const [_Home()]); // reset
      await r.push(const _Protected());
      expect(r.stack, [const _Home(), const _Protected()]);
    });

    test('async guards work, navigation awaits them', () async {
      final r = GateRouter<_R>(
        initial: const _Home(),
        guards: [
          (current, proposed) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return proposed;
          },
        ],
      );
      final future = r.push(const _Protected());
      // Pre-await: state unchanged.
      expect(r.stack, [const _Home()]);
      await future;
      expect(r.stack, [const _Home(), const _Protected()]);
    });

    test('multiple guards run in pipeline order', () async {
      final transformations = <String>[];
      final r = GateRouter<_R>(
        initial: const _Home(),
        guards: [
          (current, proposed) {
            transformations.add('first');
            return proposed;
          },
          (current, proposed) {
            transformations.add('second');
            return proposed;
          },
        ],
      );
      await r.push(const _Protected());
      expect(transformations, ['first', 'second']);
    });

    test('a guard returning current refuses the navigation', () async {
      final r = GateRouter<_R>(
        initial: const _Home(),
        guards: [(current, proposed) => current],
      );
      await r.push(const _Protected());
      expect(r.stack, [const _Home()]);
    });

    test('serialized concurrent navigations through async guards', () async {
      final r = GateRouter<_R>(
        initial: const _Home(),
        guards: [
          (current, proposed) async {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            return proposed;
          },
        ],
      );
      // Fire two pushes without awaiting; they should land in order.
      r.push(const _Protected());
      await r.push(const _Login());
      expect(r.stack, [const _Home(), const _Protected(), const _Login()]);
    });
  });

  group('ShellRouter', () {
    test('starts on initialBranch with each branch at its initial route', () {
      final shell = ShellRouter<_R>(
        branchInitials: const [_Home(), _Login()],
        initialBranch: 1,
      );
      expect(shell.activeBranch, 1);
      expect(shell.branchCount, 2);
      expect(shell.current.stack, [const _Login()]);
      expect(shell.branches[0].stack, [const _Home()]);
    });

    test('switchTo changes active branch and notifies', () {
      final shell = ShellRouter<_R>(
        branchInitials: const [_Home(), _Login()],
      );
      var notifications = 0;
      shell.addListener(() => notifications++);

      shell.switchTo(1);
      expect(shell.activeBranch, 1);
      expect(notifications, 1);

      // No-op when already on that branch.
      shell.switchTo(1);
      expect(notifications, 1);
    });

    test('switchTo throws on out-of-range index', () {
      final shell = ShellRouter<_R>(branchInitials: const [_Home()]);
      expect(() => shell.switchTo(-1), throwsRangeError);
      expect(() => shell.switchTo(99), throwsRangeError);
    });

    test('branch mutations notify shell listeners', () async {
      final shell = ShellRouter<_R>(
        branchInitials: const [_Home(), _Login()],
      );
      var notifications = 0;
      shell.addListener(() => notifications++);

      await shell.branches[0].push(const _Protected());
      expect(notifications, 1);
      expect(
        shell.branches[0].stack,
        [const _Home(), const _Protected()],
      );
    });

    test('branches are independent — pushing in one does not affect others',
        () async {
      final shell = ShellRouter<_R>(
        branchInitials: const [_Home(), _Login()],
      );
      await shell.branches[0].push(const _Protected());
      expect(
        shell.branches[0].stack,
        [const _Home(), const _Protected()],
      );
      expect(shell.branches[1].stack, [const _Login()]);
    });
  });
}
