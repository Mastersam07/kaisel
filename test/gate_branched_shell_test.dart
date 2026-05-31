import 'package:flutter_test/flutter_test.dart';
import 'package:gate/gate.dart';

// Two distinct sealed branch types — exactly the v0.4 scenario.

sealed class _HomeRoute extends GateRoute {
  const _HomeRoute();
}

final class _HomeRoot extends _HomeRoute {
  const _HomeRoot();
}

final class _ProductDetail extends _HomeRoute {
  const _ProductDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

sealed class _DiscoverRoute extends GateRoute {
  const _DiscoverRoute();
}

final class _DiscoverRoot extends _DiscoverRoute {
  const _DiscoverRoot();
}

void main() {
  group('BranchedShellRouter', () {
    test('starts on initialBranch', () {
      final home = GateRouter<_HomeRoute>(initial: const _HomeRoot());
      final discover =
          GateRouter<_DiscoverRoute>(initial: const _DiscoverRoot());
      final shell = BranchedShellRouter(
        branches: [home, discover],
        initialBranch: 1,
      );
      addTearDown(shell.dispose);
      addTearDown(home.dispose);
      addTearDown(discover.dispose);

      expect(shell.activeBranch, 1);
      expect(shell.branchCount, 2);
      expect(identical(shell.current, discover), isTrue);
    });

    test('switchTo changes active branch and notifies', () {
      final home = GateRouter<_HomeRoute>(initial: const _HomeRoot());
      final discover =
          GateRouter<_DiscoverRoute>(initial: const _DiscoverRoot());
      final shell = BranchedShellRouter(branches: [home, discover]);
      addTearDown(shell.dispose);
      addTearDown(home.dispose);
      addTearDown(discover.dispose);

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
      final home = GateRouter<_HomeRoute>(initial: const _HomeRoot());
      final shell = BranchedShellRouter(branches: [home]);
      addTearDown(shell.dispose);
      addTearDown(home.dispose);

      expect(() => shell.switchTo(-1), throwsRangeError);
      expect(() => shell.switchTo(99), throwsRangeError);
    });

    test('currentCanPop reflects the active branch', () async {
      final home = GateRouter<_HomeRoute>(initial: const _HomeRoot());
      final discover =
          GateRouter<_DiscoverRoute>(initial: const _DiscoverRoot());
      final shell = BranchedShellRouter(branches: [home, discover]);
      addTearDown(shell.dispose);
      addTearDown(home.dispose);
      addTearDown(discover.dispose);

      expect(shell.currentCanPop, isFalse); // home is at root
      await home.push(const _ProductDetail('x'));
      expect(shell.currentCanPop, isTrue);

      // Switch to discover (which is at root).
      shell.switchTo(1);
      expect(shell.currentCanPop, isFalse);
    });

    test('popCurrent pops the active branch', () async {
      final home = GateRouter<_HomeRoute>(initial: const _HomeRoot());
      final discover =
          GateRouter<_DiscoverRoute>(initial: const _DiscoverRoot());
      final shell = BranchedShellRouter(branches: [home, discover]);
      addTearDown(shell.dispose);
      addTearDown(home.dispose);
      addTearDown(discover.dispose);

      await home.push(const _ProductDetail('x'));
      expect(home.depth, 2);

      final popped = await shell.popCurrent();
      expect(popped, isTrue);
      expect(home.depth, 1);

      // No-op at root.
      final popped2 = await shell.popCurrent();
      expect(popped2, isFalse);
    });

    test('branch mutations notify shell listeners', () async {
      final home = GateRouter<_HomeRoute>(initial: const _HomeRoot());
      final discover =
          GateRouter<_DiscoverRoute>(initial: const _DiscoverRoot());
      final shell = BranchedShellRouter(branches: [home, discover]);
      addTearDown(shell.dispose);
      addTearDown(home.dispose);
      addTearDown(discover.dispose);

      var notifications = 0;
      shell.addListener(() => notifications++);

      await home.push(const _ProductDetail('x'));
      expect(notifications, 1);

      await discover.push(const _DiscoverRoot()); // no-op (same as top)
      expect(notifications, 1); // no notify because stack unchanged

      shell.switchTo(1);
      expect(notifications, 2);
    });

    test('branches stay independent — pushing in one is invisible to others',
        () async {
      final home = GateRouter<_HomeRoute>(initial: const _HomeRoot());
      final discover =
          GateRouter<_DiscoverRoute>(initial: const _DiscoverRoot());
      final shell = BranchedShellRouter(branches: [home, discover]);
      addTearDown(shell.dispose);
      addTearDown(home.dispose);
      addTearDown(discover.dispose);

      await home.push(const _ProductDetail('a'));
      expect(home.stack, [const _HomeRoot(), const _ProductDetail('a')]);
      expect(discover.stack, [const _DiscoverRoot()]);
    });

    test('asserts that branches is non-empty', () {
      expect(
        () => BranchedShellRouter(branches: const []),
        throwsA(isA<AssertionError>()),
      );
    });

    test('asserts initialBranch is in range', () {
      final home = GateRouter<_HomeRoute>(initial: const _HomeRoot());
      addTearDown(home.dispose);

      expect(
        () => BranchedShellRouter(branches: [home], initialBranch: 5),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('GateNavigator interface', () {
    test('GateRouter implements GateNavigator', () {
      final r = GateRouter<_HomeRoute>(initial: const _HomeRoot());
      addTearDown(r.dispose);
      expect(r, isA<GateNavigator>());
      // Non-generic ops are reachable via the interface:
      final GateNavigator n = r;
      expect(n.canPop, isFalse);
    });
  });
}
