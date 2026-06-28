import 'package:kaisel_core/framework.dart' show KaiselNestedHandle;
import 'package:kaisel_core/kaisel_core.dart';
import 'package:test/test.dart';

sealed class _Top extends KaiselRoute {
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

sealed class _Home extends KaiselRoute {
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

class _LegacyStackCodec implements KaiselStackCodec<_Top> {
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

// A handle that extends (not implements) KaiselNestedHandle, so it inherits the
// default replacesHistoryEntry. Real handles (shell controller, module mount)
// all override it; this pins the documented default for any future subclass.
class _DefaultHandle extends KaiselNestedHandle {
  @override
  Type get configType => KaiselModuleConfig;

  @override
  KaiselNestedConfig captureConfig() =>
      KaiselModuleConfig(stack: const [_HomeRoot()]);

  @override
  Future<void> restoreFromConfig(KaiselNestedConfig config) async {}

  @override
  void addListener(void Function() listener) {}

  @override
  void removeListener(void Function() listener) {}
}

// Extends (not implements) KaiselConfigCodec, exercising the base class's const
// constructor. First-party codecs all implement the interface, so without this
// the super constructor is never invoked.
class _ExtConfigCodec extends KaiselConfigCodec<_Top> {
  _ExtConfigCodec();

  @override
  Uri encode(KaiselConfig<_Top> config) => Uri(path: '/');

  @override
  KaiselConfig<_Top>? decode(Uri uri) => null;
}

void main() {
  group('KaiselNestedHandle', () {
    test('replacesHistoryEntry defaults to false', () {
      expect(_DefaultHandle().replacesHistoryEntry, isFalse);
    });
  });

  group('KaiselConfig', () {
    test('equality is value-based', () {
      final a = KaiselConfig<_Top>(
        mainStack: const [_Shell()],
        nestedState: KaiselShellConfig(
          activeBranch: 0,
          activeBranchStack: [const _HomeRoot(), const _Product('x')],
        ),
      );
      final b = KaiselConfig<_Top>(
        mainStack: const [_Shell()],
        nestedState: KaiselShellConfig(
          activeBranch: 0,
          activeBranchStack: [const _HomeRoot(), const _Product('x')],
        ),
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('differs when shell state differs', () {
      final a = KaiselConfig<_Top>(mainStack: const [_Shell()]);
      final b = KaiselConfig<_Top>(
        mainStack: const [_Shell()],
        nestedState: KaiselShellConfig(
          activeBranch: 1,
          activeBranchStack: const [_HomeRoot()],
        ),
      );
      expect(a, isNot(equals(b)));
    });

    test('stackOnly builds a config with that stack and no nested state', () {
      final c = KaiselConfig<_Top>.stackOnly(const [_Shell(), _Settings()]);
      expect(c.mainStack, const [_Shell(), _Settings()]);
      expect(c.nestedState, isNull);
    });

    test('stackOnly mainStack is unmodifiable', () {
      final c = KaiselConfig<_Top>.stackOnly([const _Splash()]);
      expect(() => c.mainStack.add(const _Shell()), throwsUnsupportedError);
    });

    test('mainStack is unmodifiable', () {
      final c = KaiselConfig<_Top>(mainStack: [const _Splash()]);
      expect(() => c.mainStack.add(const _Shell()), throwsUnsupportedError);
    });

    test('rejects an empty mainStack', () {
      expect(
        () => KaiselConfig<_Top>(mainStack: const []),
        throwsA(isA<AssertionError>()),
      );
    });

    test('toString names both fields', () {
      final c = KaiselConfig<_Top>(
        mainStack: const [_Shell()],
        nestedState: KaiselModuleConfig(stack: const [_HomeRoot()]),
      );
      expect(c.toString(), startsWith('KaiselConfig(mainStack:'));
      expect(c.toString(), contains('nestedState:'));
    });
  });

  group('KaiselShellConfig', () {
    test('equality is value-based', () {
      final a = KaiselShellConfig(
        activeBranch: 2,
        activeBranchStack: const [_HomeRoot()],
      );
      final b = KaiselShellConfig(
        activeBranch: 2,
        activeBranchStack: const [_HomeRoot()],
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('differs when activeBranch differs', () {
      final a = KaiselShellConfig(
        activeBranch: 0,
        activeBranchStack: const [_HomeRoot()],
      );
      final b = KaiselShellConfig(
        activeBranch: 1,
        activeBranchStack: const [_HomeRoot()],
      );
      expect(a, isNot(equals(b)));
    });

    test('differs when activeBranchStack differs', () {
      final a = KaiselShellConfig(
        activeBranch: 0,
        activeBranchStack: const [_HomeRoot()],
      );
      final b = KaiselShellConfig(
        activeBranch: 0,
        activeBranchStack: const [_HomeRoot(), _Product('x')],
      );
      expect(a, isNot(equals(b)));
    });

    test('rejects an empty activeBranchStack', () {
      expect(
        () => KaiselShellConfig(activeBranch: 0, activeBranchStack: const []),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects a negative activeBranch', () {
      expect(
        () => KaiselShellConfig(
          activeBranch: -1,
          activeBranchStack: const [_HomeRoot()],
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('toString names both fields', () {
      final c = KaiselShellConfig(
        activeBranch: 1,
        activeBranchStack: const [_HomeRoot()],
      );
      expect(c.toString(), startsWith('KaiselShellConfig(activeBranch: 1,'));
      expect(c.toString(), contains('activeBranchStack:'));
    });
  });

  group('KaiselModuleConfig', () {
    test('equality is value-based', () {
      final a = KaiselModuleConfig(stack: const [_HomeRoot(), _Product('x')]);
      final b = KaiselModuleConfig(stack: const [_HomeRoot(), _Product('x')]);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('differs when stack differs', () {
      final a = KaiselModuleConfig(stack: const [_HomeRoot()]);
      final b = KaiselModuleConfig(stack: const [_HomeRoot(), _Product('x')]);
      expect(a, isNot(equals(b)));
    });

    test('a module config is never equal to a shell config', () {
      final module = KaiselModuleConfig(stack: const [_HomeRoot()]);
      final shell = KaiselShellConfig(
        activeBranch: 0,
        activeBranchStack: const [_HomeRoot()],
      );
      expect(module, isNot(equals(shell)));
    });

    test('rejects an empty stack', () {
      expect(
        () => KaiselModuleConfig(stack: const []),
        throwsA(isA<AssertionError>()),
      );
    });

    test('toString names the stack', () {
      final c = KaiselModuleConfig(stack: const [_HomeRoot()]);
      expect(c.toString(), startsWith('KaiselModuleConfig(stack:'));
    });
  });

  group('StackToConfigCodec adapter', () {
    test('round-trips a stack-only URL through KaiselConfig', () {
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
        KaiselConfig<_Top>(
          mainStack: const [_Shell()],
          nestedState: KaiselShellConfig(
            activeBranch: 0,
            activeBranchStack: [const _HomeRoot(), const _Product('x')],
          ),
        ),
      );
      expect(encoded.path, '/app');
    });

    test('returns null for unrecognised URLs (parser will use fallback)', () {
      const adapter = StackToConfigCodec<_Top>(_LegacyStackCodec());
      expect(adapter.decode(Uri(path: '/nope')), isNull);
    });

    test('KaiselConfigCodec can be extended, not just implemented', () {
      final codec = _ExtConfigCodec();
      expect(
        codec.encode(KaiselConfig<_Top>(mainStack: const [_Splash()])).path,
        '/',
      );
      expect(codec.decode(Uri(path: '/x')), isNull);
    });
  });

  group('KaiselRouter.restoreStack', () {
    test('replaces the stack when all routes type-check', () async {
      final r = KaiselRouter<_Home>(initial: const _HomeRoot());
      addTearDown(r.dispose);
      await r.restoreStack(const [_HomeRoot(), _Product('a')]);
      expect(r.stack, const [_HomeRoot(), _Product('a')]);
    });

    test('throws ArgumentError when a route is the wrong type', () async {
      final r = KaiselRouter<_Home>(initial: const _HomeRoot());
      addTearDown(r.dispose);
      // _Splash is _Top, not _Home — should reject before mutating.
      await expectLater(
        () => r.restoreStack(const [_Splash()]),
        throwsArgumentError,
      );
      expect(r.stack, const [_HomeRoot()]);
    });

    test('runs guards on the restored stack', () async {
      List<_Home> stripProducts(List<_Home> current, List<_Home> proposed) {
        return proposed.where((r) => r is! _Product).toList();
      }

      final r = KaiselRouter<_Home>(
        initial: const _HomeRoot(),
        guards: [stripProducts],
      );
      addTearDown(r.dispose);

      await r.restoreStack(const [_HomeRoot(), _Product('x')]);
      expect(r.stack, const [_HomeRoot()]);
    });
  });
}
