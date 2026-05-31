import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gate/gate.dart';

// Fixtures

sealed class _AppRoute extends GateRoute {
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

final class _AccountMount extends _AppRoute {
  const _AccountMount();
}

sealed class _CheckoutRoute extends GateRoute {
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

sealed class _AccountRoute extends GateRoute {
  const _AccountRoute();
}

final class _Profile extends _AccountRoute {
  const _Profile();
}

final class _PaymentMethods extends _AccountRoute {
  const _PaymentMethods();
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

class _AccountCodec extends ModuleStackCodec<_AccountRoute> {
  const _AccountCodec();

  @override
  List<String> encode(List<_AccountRoute> stack) => switch (stack.last) {
        _Profile() => const [],
        _PaymentMethods() => const ['payment-methods'],
      };

  @override
  List<_AccountRoute>? decode(List<String> segments) => switch (segments) {
        [] => const [_Profile()],
        ['payment-methods'] => const [_Profile(), _PaymentMethods()],
        _ => null,
      };
}

// A bare base codec — handles main-stack routes only.
class _MainCodec implements GateConfigCodec<_AppRoute> {
  const _MainCodec();

  @override
  Uri encode(GateConfig<_AppRoute> config) => switch (config.mainStack.last) {
        _Home() => Uri(path: '/'),
        _Settings() => Uri(path: '/settings'),
        // Mount routes shouldn't reach here when wrapped by a composer
        // — defensive fallback.
        _CheckoutMount() || _AccountMount() => Uri(path: '/'),
      };

  @override
  GateConfig<_AppRoute>? decode(Uri uri) => switch (uri.pathSegments) {
        [] || [''] => GateConfig(mainStack: const [_Home()]),
        ['settings'] => GateConfig(mainStack: const [_Settings()]),
        _ => null,
      };
}

void main() {
  group('ModuleStackCodec type erasure', () {
    test('encodeAny downcasts to the typed encode', () {
      const codec = _CheckoutCodec();
      // Pass as List<GateRoute> — the erased entry point.
      final result = codec.encodeAny(const <GateRoute>[_Cart(), _Shipping()]);
      expect(result, ['shipping']);
    });

    test('decodeAny upcasts the typed decode result', () {
      const codec = _CheckoutCodec();
      final result = codec.decodeAny(const ['shipping']);
      expect(result, isA<List<GateRoute>>());
      expect(result, hasLength(2));
      expect(result![0], isA<_Cart>());
      expect(result[1], isA<_Shipping>());
    });

    test('decodeAny returns null when the typed decode rejects', () {
      const codec = _CheckoutCodec();
      expect(codec.decodeAny(const ['nonsense']), isNull);
    });

    test('typed encode/decode round-trip', () {
      const codec = _CheckoutCodec();
      for (final stack in <List<_CheckoutRoute>>[
        const [_Cart()],
        const [_Cart(), _Shipping()],
        const [_Cart(), _Shipping(), _Confirm()],
      ]) {
        final encoded = codec.encode(stack);
        final decoded = codec.decode(encoded);
        expect(decoded, stack);
      }
    });
  });

  group('ConfigCodecWithModules — decode', () {
    const codec = ConfigCodecWithModules<_AppRoute>(
      baseCodec: _MainCodec(),
      modules: [
        ModuleMount(
          mountRoute: _CheckoutMount(),
          prefix: '/checkout',
          codec: _CheckoutCodec(),
        ),
        ModuleMount(
          mountRoute: _AccountMount(),
          prefix: '/account',
          codec: _AccountCodec(),
        ),
      ],
    );

    test('non-module URLs delegate to the base codec', () {
      final home = codec.decode(Uri.parse('/'));
      expect(home, isNotNull);
      expect(home!.mainStack, const [_Home()]);
      expect(home.nestedState, isNull);

      final settings = codec.decode(Uri.parse('/settings'));
      expect(settings!.mainStack, const [_Settings()]);
    });

    test('module root URL decodes to mount + module initial', () {
      final result = codec.decode(Uri.parse('/checkout'));
      expect(result, isNotNull);
      expect(result!.mainStack, const [_CheckoutMount()]);
      expect(result.nestedState, isA<GateModuleConfig>());
      final nested = result.nestedState! as GateModuleConfig;
      expect(nested.stack, const [_Cart()]);
    });

    test('deep module URL decodes to full restored stack', () {
      final result = codec.decode(Uri.parse('/checkout/confirm'));
      expect(result!.mainStack, const [_CheckoutMount()]);
      final nested = result.nestedState! as GateModuleConfig;
      expect(nested.stack, const [_Cart(), _Shipping(), _Confirm()]);
    });

    test('different module prefixes route to different module codecs', () {
      final checkout = codec.decode(Uri.parse('/checkout/shipping'));
      expect(checkout!.mainStack, const [_CheckoutMount()]);

      final account = codec.decode(Uri.parse('/account/payment-methods'));
      expect(account!.mainStack, const [_AccountMount()]);
      final nested = account.nestedState! as GateModuleConfig;
      expect(nested.stack, const [_Profile(), _PaymentMethods()]);
    });

    test(
      'URL within a known prefix but unrecognised by the module codec returns null '
      '— does NOT fall through to baseCodec',
      () {
        // /checkout/nope matches the /checkout prefix; the module
        // codec rejects ['nope']. The composer returns null
        // rather than letting baseCodec try (which would also reject,
        // but the principle matters — the URL is in the module's
        // namespace).
        expect(codec.decode(Uri.parse('/checkout/nope')), isNull);
      },
    );

    test('URL with no matching prefix falls through to baseCodec', () {
      // /unknown isn't under any module prefix; baseCodec is asked.
      // Its decode returns null for unknown paths.
      expect(codec.decode(Uri.parse('/unknown')), isNull);
    });

    test('trailing slash in module URL is tolerated', () {
      // /checkout/ should decode the same as /checkout.
      final withSlash = codec.decode(Uri.parse('/checkout/'));
      final withoutSlash = codec.decode(Uri.parse('/checkout'));
      expect(withSlash, equals(withoutSlash));
    });
  });

  group('ConfigCodecWithModules — encode', () {
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

    test('non-module config delegates to base codec', () {
      final uri = codec.encode(GateConfig(mainStack: const [_Home()]));
      expect(uri.path, '/');
    });

    test('module config with module state encodes to prefix + segments', () {
      final uri = codec.encode(
        GateConfig(
          mainStack: const [_CheckoutMount()],
          nestedState: GateModuleConfig(
            stack: const [_Cart(), _Shipping()],
          ),
        ),
      );
      expect(uri.pathSegments, ['checkout', 'shipping']);
    });

    test('module root state encodes to just the prefix', () {
      final uri = codec.encode(
        GateConfig(
          mainStack: const [_CheckoutMount()],
          nestedState: GateModuleConfig(stack: const [_Cart()]),
        ),
      );
      expect(uri.pathSegments, ['checkout']);
    });

    test(
      'mount route on top but no module state yet encodes just the prefix',
      () {
        // Cold state: mount has been pushed but module widget hasn't
        // registered yet, so nestedState is null. The composer should
        // still produce a sensible URL for the mount itself rather
        // than falling through.
        final uri = codec.encode(
          GateConfig(
            mainStack: const [_CheckoutMount()],
          ),
        );
        expect(uri.pathSegments, ['checkout']);
      },
    );

    test('round-trip: decode then encode is identity for module URLs', () {
      for (final path in const [
        '/checkout',
        '/checkout/shipping',
        '/checkout/confirm',
      ]) {
        final decoded = codec.decode(Uri.parse(path));
        expect(decoded, isNotNull, reason: 'decode failed for $path');
        final encoded = codec.encode(decoded!);
        expect(encoded.path, path, reason: 'round-trip mismatch for $path');
      }
    });
  });

  group('ModuleMount prefix parsing', () {
    test('leading slash is optional', () {
      const withSlash = ConfigCodecWithModules<_AppRoute>(
        baseCodec: _MainCodec(),
        modules: [
          ModuleMount(
            mountRoute: _CheckoutMount(),
            prefix: '/checkout',
            codec: _CheckoutCodec(),
          ),
        ],
      );
      const withoutSlash = ConfigCodecWithModules<_AppRoute>(
        baseCodec: _MainCodec(),
        modules: [
          ModuleMount(
            mountRoute: _CheckoutMount(),
            prefix: 'checkout',
            codec: _CheckoutCodec(),
          ),
        ],
      );

      final a = withSlash.decode(Uri.parse('/checkout/confirm'));
      final b = withoutSlash.decode(Uri.parse('/checkout/confirm'));
      expect(a, equals(b));
    });
  });

  group('RouteModule.codec', () {
    test('defaults to null when not overridden', () {
      const module = _MinimalModule();
      expect(module.codec, isNull);
    });

    test('returns the typed codec when overridden', () {
      const module = _CheckoutModule();
      expect(module.codec, isA<ModuleStackCodec<_CheckoutRoute>>());
      // Round-trip via the typed API on the module's own codec.
      final encoded = module.codec!.encode(const [_Cart(), _Confirm()]);
      // Confirm doesn't follow Shipping in the codec's contract — but
      // the encode just looks at the last element.
      expect(encoded, ['confirm']);
    });
  });
}

class _MinimalModule extends RouteModule<_CheckoutRoute> {
  const _MinimalModule();

  @override
  List<_CheckoutRoute> get initialStack => const [_Cart()];

  @override
  Widget buildPage(BuildContext context, _CheckoutRoute route) =>
      throw UnimplementedError();
}

class _CheckoutModule extends RouteModule<_CheckoutRoute> {
  const _CheckoutModule();

  @override
  List<_CheckoutRoute> get initialStack => const [_Cart()];

  @override
  Widget buildPage(BuildContext context, _CheckoutRoute route) =>
      throw UnimplementedError();

  @override
  ModuleStackCodec<_CheckoutRoute>? get codec => const _CheckoutCodec();
}
