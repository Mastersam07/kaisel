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

final class _FeedItem extends _DiscoverRoute {
  const _FeedItem(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
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
      expect(notifications, 1, reason: 'home push should notify shell');

      shell.switchTo(1);
      expect(notifications, 2, reason: 'tab switch should notify shell');

      await discover.push(const _FeedItem('y'));
      expect(notifications, 3, reason: 'discover push should notify shell');
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

  group('BranchedShellRouter capture / restore', () {
    test('captureConfig reflects the active branch and its stack', () async {
      final home = GateRouter<_HomeRoute>(initial: const _HomeRoot());
      final discover =
          GateRouter<_DiscoverRoute>(initial: const _DiscoverRoot());
      final shell = BranchedShellRouter(branches: [home, discover]);
      addTearDown(shell.dispose);
      addTearDown(home.dispose);
      addTearDown(discover.dispose);

      // Home tab, depth 2.
      await home.push(const _ProductDetail('x'));
      final c1 = shell.captureConfig();
      expect(c1.activeBranch, 0);
      expect(c1.activeBranchStack, const [_HomeRoot(), _ProductDetail('x')]);

      // Switch tabs — capture reflects discover, NOT home's deep state.
      shell.switchTo(1);
      final c2 = shell.captureConfig();
      expect(c2.activeBranch, 1);
      expect(c2.activeBranchStack, const [_DiscoverRoot()]);
    });

    test('restoreFromConfig replays the captured snapshot', () async {
      final home = GateRouter<_HomeRoute>(initial: const _HomeRoot());
      final discover =
          GateRouter<_DiscoverRoute>(initial: const _DiscoverRoot());
      final shell = BranchedShellRouter(branches: [home, discover]);
      addTearDown(shell.dispose);
      addTearDown(home.dispose);
      addTearDown(discover.dispose);

      await shell.restoreFromConfig(
        GateShellConfig(
          activeBranch: 0,
          activeBranchStack: const [_HomeRoot(), _ProductDetail('y')],
        ),
      );

      expect(shell.activeBranch, 0);
      expect(home.stack, const [_HomeRoot(), _ProductDetail('y')]);
    });

    test('restoreFromConfig leaves inactive branches alone', () async {
      final home = GateRouter<_HomeRoute>(initial: const _HomeRoot());
      final discover =
          GateRouter<_DiscoverRoute>(initial: const _DiscoverRoot());
      final shell = BranchedShellRouter(branches: [home, discover]);
      addTearDown(shell.dispose);
      addTearDown(home.dispose);
      addTearDown(discover.dispose);

      // Put home into a non-default state.
      await home.push(const _ProductDetail('preserved'));

      // Restore discover; home's stack must not be reset.
      await shell.restoreFromConfig(
        GateShellConfig(
          activeBranch: 1,
          activeBranchStack: const [_DiscoverRoot()],
        ),
      );

      expect(shell.activeBranch, 1);
      expect(home.stack, const [_HomeRoot(), _ProductDetail('preserved')]);
    });

    test('restoreFromConfig throws on out-of-range activeBranch', () async {
      final home = GateRouter<_HomeRoute>(initial: const _HomeRoot());
      final shell = BranchedShellRouter(branches: [home]);
      addTearDown(shell.dispose);
      addTearDown(home.dispose);

      await expectLater(
        () => shell.restoreFromConfig(
          GateShellConfig(
            activeBranch: 99,
            activeBranchStack: const [_HomeRoot()],
          ),
        ),
        throwsRangeError,
      );
    });

    test('restoreFromConfig with a route of the wrong type throws', () async {
      final home = GateRouter<_HomeRoute>(initial: const _HomeRoot());
      final discover =
          GateRouter<_DiscoverRoute>(initial: const _DiscoverRoot());
      final shell = BranchedShellRouter(branches: [home, discover]);
      addTearDown(shell.dispose);
      addTearDown(home.dispose);
      addTearDown(discover.dispose);

      // Try to put a DiscoverRoute into the Home branch.
      await expectLater(
        () => shell.restoreFromConfig(
          GateShellConfig(
            activeBranch: 0,
            activeBranchStack: const [_DiscoverRoot()],
          ),
        ),
        throwsArgumentError,
      );
    });

    test('capture-then-restore round-trip yields the same state', () async {
      final home = GateRouter<_HomeRoute>(initial: const _HomeRoot());
      final discover =
          GateRouter<_DiscoverRoute>(initial: const _DiscoverRoot());
      final shell = BranchedShellRouter(branches: [home, discover]);
      addTearDown(shell.dispose);
      addTearDown(home.dispose);
      addTearDown(discover.dispose);

      await home.push(const _ProductDetail('round-trip'));
      shell.switchTo(0);

      final captured = shell.captureConfig();

      // Reset, then restore from the snapshot.
      shell.switchTo(1);
      await home.pop();

      await shell.restoreFromConfig(captured);

      expect(shell.activeBranch, captured.activeBranch);
      expect(shell.captureConfig(), equals(captured));
    });
  });
}
