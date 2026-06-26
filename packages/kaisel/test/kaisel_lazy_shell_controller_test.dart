import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

sealed class _R extends KaiselRoute {
  const _R();
}

final class _Root extends _R {
  const _Root();
}

final class _Detail extends _R {
  const _Detail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

class _SpyRouter extends KaiselRouter<_R> {
  _SpyRouter(this.index) : super(initial: const _Root());

  final int index;
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

// Factories over [count] branches plus the list they record themselves into, in
// construction order — the spine of every laziness assertion below.
({List<KaiselNavigator Function()> factories, List<_SpyRouter> built}) _spies(
  int count,
) {
  final built = <_SpyRouter>[];
  final factories = <KaiselNavigator Function()>[
    for (var i = 0; i < count; i++)
      () {
        final router = _SpyRouter(i);
        built.add(router);
        return router;
      },
  ];
  return (factories: factories, built: built);
}

void main() {
  group('BranchedShellRouter.lazy', () {
    test('builds only the initial branch on construction', () {
      final spies = _spies(3);
      final shell = BranchedShellRouter.lazy(
        branchFactories: spies.factories,
        initialBranch: 0,
      );
      addTearDown(shell.dispose);

      expect(shell.branchCount, 3);
      expect(shell.activeBranch, 0);
      expect(spies.built.map((r) => r.index), [0]);
      expect(shell.branches, hasLength(1));
    });

    test('honours initialBranch and builds only it', () {
      final spies = _spies(3);
      final shell = BranchedShellRouter.lazy(
        branchFactories: spies.factories,
        initialBranch: 2,
      );
      addTearDown(shell.dispose);

      expect(shell.activeBranch, 2);
      expect(spies.built.map((r) => r.index), [2]);
      expect(identical(shell.current, spies.built.single), isTrue);
    });

    test('switchTo builds the target branch on first activation, once', () {
      final spies = _spies(3);
      final shell = BranchedShellRouter.lazy(branchFactories: spies.factories);
      addTearDown(shell.dispose);

      expect(spies.built.map((r) => r.index), [0]);

      shell.switchTo(2);
      expect(shell.activeBranch, 2);
      expect(spies.built.map((r) => r.index), [0, 2]);

      shell.switchTo(0);
      shell.switchTo(2);
      expect(spies.built.map((r) => r.index), [0, 2]);
      expect(shell.branches, hasLength(2));
    });

    test('switchTo notifies, and is a no-op when already active', () {
      final spies = _spies(2);
      var notifications = 0;
      final shell = BranchedShellRouter.lazy(branchFactories: spies.factories)
        ..addListener(() => notifications++);
      addTearDown(shell.dispose);

      shell.switchTo(0);
      expect(notifications, 0);

      shell.switchTo(1);
      expect(notifications, 1);
    });

    test('switchTo out of range throws RangeError', () {
      final spies = _spies(1);
      final shell = BranchedShellRouter.lazy(branchFactories: spies.factories);
      addTearDown(shell.dispose);
      expect(() => shell.switchTo(1), throwsRangeError);
      expect(() => shell.switchTo(-1), throwsRangeError);
    });

    test('branchAt out of range throws RangeError', () {
      final spies = _spies(2);
      final shell = BranchedShellRouter.lazy(branchFactories: spies.factories);
      addTearDown(shell.dispose);
      expect(() => shell.branchAt(2), throwsRangeError);
      expect(() => shell.branchAt(-1), throwsRangeError);
    });

    test(
      'currentCanPop / popCurrent operate on the lazily-built branch',
      () async {
        final spies = _spies(2);
        final shell = BranchedShellRouter.lazy(
          branchFactories: spies.factories,
        );
        addTearDown(shell.dispose);

        shell.switchTo(1);
        final branch1 = spies.built.firstWhere((r) => r.index == 1);
        expect(shell.currentCanPop, isFalse);

        await branch1.push(const _Detail('a'));
        expect(shell.currentCanPop, isTrue);

        await shell.popCurrent();
        expect(branch1.stack, hasLength(1));
      },
    );
  });

  group('BranchedShellRouter.lazy capture/restore', () {
    test(
      'captures the active branch only, without building inactive ones',
      () async {
        final spies = _spies(2);
        final shell = BranchedShellRouter.lazy(
          branchFactories: spies.factories,
        );
        addTearDown(shell.dispose);

        await spies.built.single.push(const _Detail('x'));
        final config = shell.captureConfig();
        expect(config.activeBranch, 0);
        expect(config.activeBranchStack, [const _Root(), const _Detail('x')]);
        expect(shell.branches, hasLength(1));
      },
    );

    test(
      'restoreFromConfig builds the target branch and replays its stack',
      () async {
        final spies = _spies(3);
        final shell = BranchedShellRouter.lazy(
          branchFactories: spies.factories,
        );
        addTearDown(shell.dispose);

        await shell.restoreFromConfig(
          KaiselShellConfig(
            activeBranch: 2,
            activeBranchStack: const [_Root(), _Detail('deep')],
          ),
        );

        expect(shell.activeBranch, 2);
        expect(spies.built.map((r) => r.index), [0, 2]);
        final restored = spies.built.firstWhere((r) => r.index == 2);
        expect(restored.stack, [const _Root(), const _Detail('deep')]);
      },
    );

    test(
      'restoreFromConfig ignores an out-of-range branch and builds nothing',
      () async {
        final spies = _spies(2);
        final shell = BranchedShellRouter.lazy(
          branchFactories: spies.factories,
        );
        addTearDown(shell.dispose);

        await shell.restoreFromConfig(
          KaiselShellConfig(
            activeBranch: 5,
            activeBranchStack: const [_Root()],
          ),
        );

        expect(shell.activeBranch, 0);
        expect(spies.built.map((r) => r.index), [0]);
      },
    );
  });

  group('BranchedShellRouter disposal ownership', () {
    test('lazy shell disposes the branches it built, not the unbuilt ones', () {
      final spies = _spies(3);
      final shell = BranchedShellRouter.lazy(branchFactories: spies.factories);
      shell.switchTo(2);

      shell.dispose();

      expect(spies.built.map((r) => r.index), [0, 2]);
      expect(spies.built.every((r) => r.disposed), isTrue);
    });

    test('eager shell does not dispose externally-owned branches', () {
      final a = _SpyRouter(0);
      final b = _SpyRouter(1);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final shell = BranchedShellRouter(branches: [a, b]);

      shell.dispose();

      expect(a.disposed, isFalse);
      expect(b.disposed, isFalse);
    });
  });
}
