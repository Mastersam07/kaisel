import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gate/gate.dart';

sealed class _R extends GateRoute {
  const _R();
}

final class _Home extends _R {
  const _Home();
}

final class _Settings extends _R {
  const _Settings();
}

final class _ProductDetail extends _R {
  const _ProductDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

class _StackCodec implements GateStackCodec<_R> {
  const _StackCodec();

  @override
  Uri encode(List<_R> stack) => switch (stack.last) {
        _Home() => Uri(path: '/'),
        _Settings() => Uri(path: '/settings'),
        _ProductDetail(:final id) => Uri(path: '/products/$id'),
      };

  @override
  List<_R>? decode(Uri uri) => switch (uri.pathSegments) {
        [] || [''] => const [_Home()],
        // Multi-route decode — settings restores a 2-deep stack so
        // back goes to home.
        ['settings'] => const [_Home(), _Settings()],
        ['products', final id] => [const _Home(), _ProductDetail(id)],
        _ => null,
      };
}

class _SingleCodec implements GateCodec<_R> {
  const _SingleCodec();

  @override
  Uri encode(_R route) => switch (route) {
        _Home() => Uri(path: '/'),
        _Settings() => Uri(path: '/settings'),
        _ProductDetail(:final id) => Uri(path: '/products/$id'),
      };

  @override
  _R? decode(Uri uri) => switch (uri.pathSegments) {
        [] || [''] => const _Home(),
        ['settings'] => const _Settings(),
        ['products', final id] => _ProductDetail(id),
        _ => null,
      };
}

void main() {
  group('GateStackCodec', () {
    const codec = _StackCodec();

    test('encodes the top of the stack', () {
      expect(codec.encode(const [_Home()]).path, '/');
      expect(codec.encode(const [_Home(), _Settings()]).path, '/settings');
      expect(
        codec.encode(const [_Home(), _ProductDetail('sku-42')]).path,
        '/products/sku-42',
      );
    });

    test('decodes URLs into deep stacks', () {
      expect(codec.decode(Uri.parse('/')), const [_Home()]);
      expect(
        codec.decode(Uri.parse('/settings')),
        const [_Home(), _Settings()],
      );
      expect(
        codec.decode(Uri.parse('/products/sku-1')),
        [const _Home(), const _ProductDetail('sku-1')],
      );
    });

    test('returns null on unrecognised URLs', () {
      expect(codec.decode(Uri.parse('/nope')), isNull);
    });
  });

  group('GateSingleStackCodec adapter', () {
    const inner = _SingleCodec();
    const adapted = GateSingleStackCodec<_R>(inner);

    test('encodes the top of the stack', () {
      expect(adapted.encode(const [_Home()]).path, '/');
      expect(
        adapted.encode(const [_Home(), _Settings()]).path,
        '/settings',
      );
    });

    test('decodes to a depth-1 stack', () {
      expect(adapted.decode(Uri.parse('/settings')), const [_Settings()]);
      expect(adapted.decode(Uri.parse('/nope')), isNull);
    });
  });

  group('GateRouteInformationParser', () {
    test('stack constructor decodes deep stacks', () async {
      // v0.5: bare constructor now takes a GateConfigCodec. Stack-only
      // codecs go through the .fromStackCodec migration helper.
      final parser = GateRouteInformationParser<_R>.fromStackCodec(
        codec: const _StackCodec(),
        fallback: const [_Home()],
      );
      final result = await parser.parseRouteInformation(
        RouteInformation(uri: Uri.parse('/settings')),
      );
      expect(result.mainStack, const [_Home(), _Settings()]);
      expect(result.nestedState, isNull);
    });

    test('stack constructor falls back on unrecognised URLs', () async {
      final parser = GateRouteInformationParser<_R>.fromStackCodec(
        codec: const _StackCodec(),
        fallback: const [_Home()],
      );
      final result = await parser.parseRouteInformation(
        RouteInformation(uri: Uri.parse('/nope')),
      );
      expect(result.mainStack, const [_Home()]);
      expect(result.nestedState, isNull);
    });

    test('.single constructor wraps a legacy codec', () async {
      final parser = GateRouteInformationParser<_R>.single(
        codec: const _SingleCodec(),
        fallback: const _Home(),
      );
      final result = await parser.parseRouteInformation(
        RouteInformation(uri: Uri.parse('/settings')),
      );
      expect(result.mainStack, const [_Settings()]);
      expect(result.nestedState, isNull);
    });

    test('restoreRouteInformation encodes the configuration', () {
      final parser = GateRouteInformationParser<_R>.fromStackCodec(
        codec: const _StackCodec(),
        fallback: const [_Home()],
      );
      final info = parser.restoreRouteInformation(
        GateConfig<_R>(mainStack: const [_Home(), _Settings()]),
      );
      expect(info?.uri.path, '/settings');
    });
  });
}
