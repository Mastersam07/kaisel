import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gate/gate.dart';
// GateNestedHandle isn't part of the public barrel — most apps don't
// need to implement it. Tests reach into src/ to fabricate fake
// handles that exercise the delegate's registration machinery.
import 'package:gate/src/gate_config.dart' show GateNestedHandle;

// Minimal fixtures.

sealed class _TestRoute extends GateRoute {
  const _TestRoute();
}

final class _TestRoot extends _TestRoute {
  const _TestRoot();
}

final class _OtherRoute extends _TestRoute {
  const _OtherRoute();
}

// Fake nested handles. Implementations of GateNestedHandle that
// record what restoreFromConfig was called with, so tests can observe
// dispatch behavior without spinning up widget trees.

class _FakeShellHandle extends ChangeNotifier implements GateNestedHandle {
  GateNestedConfig? lastRestored;
  GateShellConfig captureValue = GateShellConfig(
    activeBranch: 0,
    activeBranchStack: const [_TestRoot()],
  );

  @override
  Type get configType => GateShellConfig;

  @override
  GateShellConfig captureConfig() => captureValue;

  @override
  Future<void> restoreFromConfig(GateNestedConfig config) async {
    lastRestored = config;
  }
}

class _FakeModuleHandle extends ChangeNotifier implements GateNestedHandle {
  GateNestedConfig? lastRestored;
  GateModuleConfig captureValue = GateModuleConfig(stack: const [_TestRoot()]);

  @override
  Type get configType => GateModuleConfig;

  @override
  GateModuleConfig captureConfig() => captureValue;

  @override
  Future<void> restoreFromConfig(GateNestedConfig config) async {
    lastRestored = config;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('configType matches runtimeType', () {
    // The whole nested-host matching mechanism rests on
    //
    //   handle.configType == capturedConfig.runtimeType
    //
    // being true whenever the handle and config describe the same
    // nested kind. For non-generic config classes in current Dart
    // this is unambiguous, but pin it explicitly — a future Dart
    // version that synthesised different Type objects for the same
    // class via inference would silently break cold-start deep links
    // otherwise.

    test('GateShellConfig: Type literal equals runtimeType', () {
      final config = GateShellConfig(
        activeBranch: 0,
        activeBranchStack: const [_TestRoot()],
      );
      expect(config.runtimeType, GateShellConfig);
      expect(GateShellConfig, config.runtimeType);
    });

    test('GateModuleConfig: Type literal equals runtimeType', () {
      final config = GateModuleConfig(stack: const [_TestRoot()]);
      expect(config.runtimeType, GateModuleConfig);
      expect(GateModuleConfig, config.runtimeType);
    });

    test('GateShellConfig and GateModuleConfig have distinct Types', () {
      // Defensive: if these were ever equal (e.g. a future bug where
      // both inherited from a common erased type at runtime), the
      // dispatch logic would route a shell config to a module handle
      // and vice versa.
      expect(GateShellConfig, isNot(GateModuleConfig));
    });

    test(
      "BranchedShellRouter.configType matches its captureConfig's runtimeType",
      () {
        final branch = GateRouter<_TestRoute>(initial: const _TestRoot());
        addTearDown(branch.dispose);
        final shell = BranchedShellRouter(branches: [branch]);
        addTearDown(shell.dispose);

        expect(shell.configType, GateShellConfig);
        expect(shell.captureConfig().runtimeType, shell.configType);
      },
    );

    test(
      'fake handles round-trip their declared configType through capture',
      () {
        final shellHandle = _FakeShellHandle();
        expect(
          shellHandle.captureConfig().runtimeType,
          shellHandle.configType,
        );

        final moduleHandle = _FakeModuleHandle();
        expect(
          moduleHandle.captureConfig().runtimeType,
          moduleHandle.configType,
        );
      },
    );
  });

  group('GateRouterDelegate nested-host registration', () {
    late GateRouter<_TestRoute> router;
    late GateRouterDelegate<_TestRoute> delegate;

    setUp(() {
      router = GateRouter<_TestRoute>(initial: const _TestRoot());
      delegate = GateRouterDelegate<_TestRoute>(
        router: router,
        builder: (_, __) => const SizedBox.shrink(),
      );
    });

    tearDown(() {
      delegate.dispose();
      router.dispose();
    });

    test(
      'pending module state is NOT applied when a shell handle registers',
      () async {
        await delegate.setNewRoutePath(
          GateConfig<_TestRoute>(
            mainStack: const [_TestRoot()],
            nestedState: GateModuleConfig(stack: const [_OtherRoute()]),
          ),
        );

        final shell = _FakeShellHandle();
        delegate.registerNested(shell);

        // configType mismatch — shell handle must not be called.
        expect(shell.lastRestored, isNull);
      },
    );

    test(
      'pending module state IS applied when a module handle registers',
      () async {
        await delegate.setNewRoutePath(
          GateConfig<_TestRoute>(
            mainStack: const [_TestRoot()],
            nestedState: GateModuleConfig(stack: const [_OtherRoute()]),
          ),
        );

        final module = _FakeModuleHandle();
        delegate.registerNested(module);

        expect(module.lastRestored, isA<GateModuleConfig>());
        final restored = module.lastRestored! as GateModuleConfig;
        expect(restored.stack, hasLength(1));
        expect(restored.stack.single, isA<_OtherRoute>());
      },
    );

    test(
      'pending state survives a non-matching registration and is consumed by '
      'a later matching one',
      () async {
        await delegate.setNewRoutePath(
          GateConfig<_TestRoute>(
            mainStack: const [_TestRoot()],
            nestedState: GateModuleConfig(stack: const [_OtherRoute()]),
          ),
        );

        // Wrong-kind handle first. Pending should NOT be cleared.
        final shell = _FakeShellHandle();
        delegate.registerNested(shell);
        expect(shell.lastRestored, isNull);

        // Right-kind handle second. Pending should be applied here.
        final module = _FakeModuleHandle();
        delegate.registerNested(module);
        expect(module.lastRestored, isA<GateModuleConfig>());

        // Now register a fresh module handle. Pending is gone — the
        // second module handle should NOT receive the (already-
        // applied) config.
        final module2 = _FakeModuleHandle();
        delegate.registerNested(module2);
        expect(module2.lastRestored, isNull);
      },
    );

    test('currentConfiguration captures the most-recently registered handle',
        () {
      final shell = _FakeShellHandle();
      shell.captureValue = GateShellConfig(
        activeBranch: 1,
        activeBranchStack: const [_TestRoot()],
      );
      delegate.registerNested(shell);
      expect(delegate.currentConfiguration.nestedState, isA<GateShellConfig>());
      expect(
        (delegate.currentConfiguration.nestedState! as GateShellConfig)
            .activeBranch,
        1,
      );

      // Register a module handle on top. The configuration now
      // reflects the module — LIFO.
      final module = _FakeModuleHandle();
      delegate.registerNested(module);
      expect(
        delegate.currentConfiguration.nestedState,
        isA<GateModuleConfig>(),
      );

      // Unregister the module; the shell becomes active again.
      delegate.unregisterNested(module);
      expect(delegate.currentConfiguration.nestedState, isA<GateShellConfig>());
    });

    test('re-registering an existing handle moves it to the top', () {
      final shell = _FakeShellHandle();
      final module = _FakeModuleHandle();

      delegate.registerNested(shell);
      delegate.registerNested(module);
      expect(
        delegate.currentConfiguration.nestedState,
        isA<GateModuleConfig>(),
      );

      // Re-register the shell — it should now be the active one.
      delegate.registerNested(shell);
      expect(delegate.currentConfiguration.nestedState, isA<GateShellConfig>());
    });

    test(
      'registering the same handle twice consecutively is a no-op for the '
      'pending mechanism',
      () async {
        await delegate.setNewRoutePath(
          GateConfig<_TestRoute>(
            mainStack: const [_TestRoot()],
            nestedState: GateShellConfig(
              activeBranch: 0,
              activeBranchStack: const [_OtherRoute()],
            ),
          ),
        );

        final shell = _FakeShellHandle();
        delegate.registerNested(shell);
        expect(shell.lastRestored, isA<GateShellConfig>());

        // Reset the recorder and re-register. The handle is already
        // at the top of the stack, so registerNested should early-out
        // and NOT re-apply (already-cleared) pending state, and NOT
        // re-trigger restoreFromConfig with stale data.
        shell.lastRestored = null;
        delegate.registerNested(shell);
        expect(shell.lastRestored, isNull);
      },
    );

    test('unregistering a never-registered handle is a safe no-op', () {
      final shell = _FakeShellHandle();
      expect(() => delegate.unregisterNested(shell), returnsNormally);
      expect(delegate.currentConfiguration.nestedState, isNull);
    });

    test('unregistering empties the active slot when the last handle goes', () {
      final shell = _FakeShellHandle();
      delegate.registerNested(shell);
      expect(delegate.currentConfiguration.nestedState, isA<GateShellConfig>());

      delegate.unregisterNested(shell);
      expect(delegate.currentConfiguration.nestedState, isNull);
    });

    test(
      'setNewRoutePath with an already-registered matching handle applies '
      'immediately',
      () async {
        final module = _FakeModuleHandle();
        delegate.registerNested(module);

        await delegate.setNewRoutePath(
          GateConfig<_TestRoute>(
            mainStack: const [_TestRoot()],
            nestedState: GateModuleConfig(stack: const [_OtherRoute()]),
          ),
        );

        expect(module.lastRestored, isA<GateModuleConfig>());
        final restored = module.lastRestored! as GateModuleConfig;
        expect(restored.stack.single, isA<_OtherRoute>());
      },
    );
  });
}
