import 'package:kaisel_core/kaisel_core.dart';
import 'package:test/test.dart';

sealed class _AppRoute extends KaiselRoute {
  const _AppRoute();
}

final class _Home extends _AppRoute {
  const _Home();
}

final class _Settings extends _AppRoute {
  const _Settings();
}

final class _CheckoutMount extends _AppRoute {
  const _CheckoutMount();
}

sealed class _CheckoutRoute extends KaiselRoute {
  const _CheckoutRoute();
}

final class _Cart extends _CheckoutRoute {
  const _Cart();
}

final class _Shipping extends _CheckoutRoute {
  const _Shipping();
}

final class _Confirm extends _CheckoutRoute {
  const _Confirm();
}

class _CheckoutCodec extends ModuleStackCodec<_CheckoutRoute> {
  const _CheckoutCodec();

  @override
  List<String> encode(List<_CheckoutRoute> stack) => switch (stack.last) {
    _Cart() => const [],
    _Shipping() => const ['shipping'],
    _Confirm() => const ['confirm'],
  };

  @override
  List<_CheckoutRoute>? decode(List<String> segments) => switch (segments) {
    [] => const [_Cart()],
    ['shipping'] => const [_Cart(), _Shipping()],
    ['confirm'] => const [_Cart(), _Shipping(), _Confirm()],
    _ => null,
  };
}

class _MainCodec implements KaiselConfigCodec<_AppRoute> {
  const _MainCodec();

  @override
  Uri encode(KaiselConfig<_AppRoute> config) => switch (config.mainStack.last) {
    _Home() => Uri(path: '/'),
    _Settings() => Uri(path: '/settings'),
    // Mount routes shouldn't reach the base codec when wrapped by a
    // composer; defensive fallback.
    _CheckoutMount() => Uri(path: '/'),
  };

  @override
  KaiselConfig<_AppRoute>? decode(Uri uri) => switch (uri.pathSegments) {
    [] || [''] => KaiselConfig(mainStack: const [_Home()]),
    ['settings'] => KaiselConfig(mainStack: const [_Settings()]),
    _ => null,
  };
}

void main() {
  group('ModuleStackCodec encode/decode round-trip', () {
    const codec = _CheckoutCodec();

    test('typed encode then decode restores the original stack', () {
      for (final stack in const <List<_CheckoutRoute>>[
        [_Cart()],
        [_Cart(), _Shipping()],
        [_Cart(), _Shipping(), _Confirm()],
      ]) {
        final encoded = codec.encode(stack);
        expect(codec.decode(encoded), stack);
      }
    });

    test('root state encodes to const [] (prefix alone suffices)', () {
      expect(codec.encode(const [_Cart()]), isEmpty);
    });
  });

  group('UntypedModuleStackCodec bridge (encodeAny/decodeAny)', () {
    const codec = _CheckoutCodec();
    const UntypedModuleStackCodec untyped = _CheckoutCodec();

    test('encodeAny equals the typed encode of the same stack', () {
      const stack = <_CheckoutRoute>[_Cart(), _Shipping()];
      expect(
        untyped.encodeAny(const <KaiselRoute>[_Cart(), _Shipping()]),
        codec.encode(stack),
      );
      expect(untyped.encodeAny(const <KaiselRoute>[_Cart(), _Shipping()]), [
        'shipping',
      ]);
    });

    test('decodeAny equals the typed decode and upcasts to KaiselRoute', () {
      final any = untyped.decodeAny(const ['shipping']);
      expect(any, codec.decode(const ['shipping']));
      expect(any, isA<List<KaiselRoute>>());
      expect(any, hasLength(2));
      final decoded = any ?? const <KaiselRoute>[];
      expect(decoded.first, isA<_Cart>());
      expect(decoded.last, isA<_Shipping>());
    });

    test('decodeAny returns null for segments the typed decode rejects', () {
      expect(untyped.decodeAny(const ['nonsense']), isNull);
      expect(codec.decode(const ['nonsense']), isNull);
    });
  });

  group('ConfigCodecWithModules composes host codec + mounted module', () {
    const codec = ConfigCodecWithModules<_AppRoute>(
      baseCodec: _MainCodec(),
      modules: [
        ModuleMount(
          mountRoute: _CheckoutMount(),
          prefix: '/checkout',
          codec: _CheckoutCodec(),
        ),
      ],
    );

    test('encode of a module-top config produces a URI under the prefix', () {
      final uri = codec.encode(
        KaiselConfig(
          mainStack: const [_CheckoutMount()],
          nestedState: KaiselModuleConfig(stack: const [_Cart(), _Shipping()]),
        ),
      );
      expect(uri.path, '/checkout/shipping');
      expect(uri.pathSegments, ['checkout', 'shipping']);
    });

    test('encode of a module-top config with no nested state yields the prefix '
        'alone', () {
      // Transient: the mount route is on top but no KaiselModuleConfig has been
      // registered yet (just pushed, or a codec produced this state). The
      // composer falls back to encoding the mount prefix alone.
      final uri = codec.encode(
        KaiselConfig(mainStack: const [_CheckoutMount()]),
      );
      expect(uri.pathSegments, ['checkout']);
    });

    test('encode of a plain (non-module) top delegates to the host codec', () {
      expect(codec.encode(KaiselConfig(mainStack: const [_Home()])).path, '/');
      expect(
        codec.encode(KaiselConfig(mainStack: const [_Settings()])).path,
        '/settings',
      );
    });

    test(
      'decode of a module URL yields mount on main stack + module state',
      () {
        final result = codec.decode(Uri.parse('/checkout/shipping'));
        expect(result, isNotNull);
        final config = result ?? KaiselConfig(mainStack: const [_Home()]);
        expect(config.mainStack, const [_CheckoutMount()]);
        expect(config.nestedState, isA<KaiselModuleConfig>());
        final nested = config.nestedState;
        expect(
          nested,
          isA<KaiselModuleConfig>().having((n) => n.stack, 'stack', const [
            _Cart(),
            _Shipping(),
          ]),
        );
      },
    );

    test('decode of a URL matching no module and no host route is null', () {
      expect(codec.decode(Uri.parse('/unknown')), isNull);
      // Under the module prefix but rejected by the module codec — the
      // composer returns null and does NOT fall through to the host codec.
      expect(codec.decode(Uri.parse('/checkout/nope')), isNull);
    });

    test('decode then encode is identity for module URLs', () {
      for (final path in const [
        '/checkout',
        '/checkout/shipping',
        '/checkout/confirm',
      ]) {
        final decoded = codec.decode(Uri.parse(path));
        expect(decoded, isNotNull, reason: 'decode failed for $path');
        final config = decoded ?? KaiselConfig(mainStack: const [_Home()]);
        expect(codec.encode(config).path, path, reason: 'round-trip $path');
      }
    });
  });
}
