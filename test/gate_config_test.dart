import 'package:flutter_test/flutter_test.dart';
import 'package:gate/gate.dart';

// Test fixtures — two distinct sealed hierarchies.

sealed class _Top extends GateRoute {
  const _Top();
}

final class _Splash extends _Top {
  const _Splash();
}

final class _Shell extends _Top {
  const _Shell();
}

final class _Settings extends _Top {
  const _Settings();
}

sealed class _Home extends GateRoute {
  const _Home();
}

final class _HomeRoot extends _Home {
  const _HomeRoot();
}

final class _Product extends _Home {
  const _Product(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

// A simple stack codec for the migration-adapter test.
class _LegacyStackCodec implements GateStackCodec<_Top> {
  const _LegacyStackCodec();

  @override
  Uri encode(List<_Top> stack) => switch (stack.last) {
    _Splash() => Uri(path: '/'),
    _Shell() => Uri(path: '/app'),
    _Settings() => Uri(path: '/settings'),
  };

  @override
  List<_Top>? decode(Uri uri) => switch (uri.pathSegments) {
    [] || [''] => const [_Splash()],
    ['app'] => const [_Shell()],
    ['settings'] => const [_Shell(), _Settings()],
    _ => null,
  };
}

void main() {
  group('GateConfig', () {
    test('equality is value-based', () {
      final a = GateConfig<_Top>(
        mainStack: const [_Shell()],
        nestedState: GateShellConfig(
          activeBranch: 0,
          activeBranchStack: [const _HomeRoot(), const _Product('x')],
        ),
      );
      final b = GateConfig<_Top>(
        mainStack: const [_Shell()],
        nestedState: GateShellConfig(
          activeBranch: 0,
          activeBranchStack: [const _HomeRoot(), const _Product('x')],
        ),
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('differs when shell state differs', () {
      final a = GateConfig<_Top>(mainStack: const [_Shell()]);
      final b = GateConfig<_Top>(
        mainStack: const [_Shell()],
        nestedState: GateShellConfig(
          activeBranch: 1,
          activeBranchStack: const [_HomeRoot()],
        ),
      );
      expect(a, isNot(equals(b)));
    });

    test('mainStack is unmodifiable', () {
      final c = GateConfig<_Top>(mainStack: [const _Splash()]);
      expect(() => c.mainStack.add(const _Shell()), throwsUnsupportedError);
    });

    test('rejects an empty mainStack', () {
      expect(
        () => GateConfig<_Top>(mainStack: const []),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('GateShellConfig', () {
    test('equality is value-based', () {
      final a = GateShellConfig(
        activeBranch: 2,
        activeBranchStack: const [_HomeRoot()],
      );
      final b = GateShellConfig(
        activeBranch: 2,
        activeBranchStack: const [_HomeRoot()],
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('rejects an empty activeBranchStack', () {
      expect(
        () => GateShellConfig(activeBranch: 0, activeBranchStack: const []),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects a negative activeBranch', () {
      expect(
        () => GateShellConfig(
          activeBranch: -1,
          activeBranchStack: const [_HomeRoot()],
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('StackToConfigCodec adapter', () {
    test('round-trips a stack-only URL through GateConfig', () {
      const adapter = StackToConfigCodec<_Top>(_LegacyStackCodec());

      final decoded = adapter.decode(Uri(path: '/settings'));
      expect(decoded, isNotNull);
      expect(decoded!.mainStack, const [_Shell(), _Settings()]);
      expect(decoded.nestedState, isNull);

      final encoded = adapter.encode(decoded);
      expect(encoded.path, '/settings');
    });

    test('drops shell state on encode (stack codec has nowhere to put it)', () {
      const adapter = StackToConfigCodec<_Top>(_LegacyStackCodec());
      final encoded = adapter.encode(
        GateConfig<_Top>(
          mainStack: const [_Shell()],
          nestedState: GateShellConfig(
            activeBranch: 0,
            activeBranchStack: [const _HomeRoot(), const _Product('x')],
          ),
        ),
      );
      // No /home/products/x — just /app.
      expect(encoded.path, '/app');
    });

    test('returns null for unrecognised URLs (parser will use fallback)', () {
      const adapter = StackToConfigCodec<_Top>(_LegacyStackCodec());
      expect(adapter.decode(Uri(path: '/nope')), isNull);
    });
  });

  group('GateRouter.restoreStack', () {
    test('replaces the stack when all routes type-check', () async {
      final r = GateRouter<_Home>(initial: const _HomeRoot());
      addTearDown(r.dispose);
      await r.restoreStack(const [_HomeRoot(), _Product('a')]);
      expect(r.stack, const [_HomeRoot(), _Product('a')]);
    });

    test('throws ArgumentError when a route is the wrong type', () async {
      final r = GateRouter<_Home>(initial: const _HomeRoot());
      addTearDown(r.dispose);
      // _Splash is _Top, not _Home — should reject before mutating.
      await expectLater(
        () => r.restoreStack(const [_Splash()]),
        throwsArgumentError,
      );
      expect(r.stack, const [_HomeRoot()]);
    });

    test('runs guards on the restored stack', () async {
      // A guard that strips _Product routes — restoreStack should
      // see the effect.
      List<_Home> stripProducts(List<_Home> current, List<_Home> proposed) {
        return proposed.where((r) => r is! _Product).toList();
      }

      final r = GateRouter<_Home>(
        initial: const _HomeRoot(),
        guards: [stripProducts],
      );
      addTearDown(r.dispose);

      await r.restoreStack(const [_HomeRoot(), _Product('x')]);
      expect(r.stack, const [_HomeRoot()]);
    });
  });
}
