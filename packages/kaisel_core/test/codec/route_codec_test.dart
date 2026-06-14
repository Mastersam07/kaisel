import 'package:kaisel_core/codec.dart';
import 'package:kaisel_core/kaisel_core.dart';
import 'package:test/test.dart';

sealed class _App extends KaiselRoute {
  const _App();
}

final class _Home extends _App {
  const _Home();
}

final class _ProductList extends _App {
  const _ProductList();
}

final class _ProductDetail extends _App {
  const _ProductDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

final class _NotFound extends _App {
  const _NotFound(this.path);
  final String path;
  @override
  List<Object?> get props => [path];
}

RouteCodec<_App> _codec() => RouteCodec<_App>(
  rules: [
    fixed(const _Home(), root),
    fixed(const _ProductList(), seg('products')),
    (seg('products') / str)
        .to((c) => _ProductDetail(c.string(0)))
        .under(const [_Home(), _ProductList()])
        .from((r) => r is _ProductDetail ? r.props : null),
  ],
  fallback: (uri) => [const _Home(), _NotFound(uri.path)],
);

void main() {
  group('decode', () {
    final codec = _codec();

    test('first matching rule wins; breadcrumb included', () {
      expect(codec.decode(Uri.parse('/'))?.mainStack, const [_Home()]);
      expect(codec.decode(Uri.parse('/products'))?.mainStack, const [
        _ProductList(),
      ]);
      expect(codec.decode(Uri.parse('/products/sku-1'))?.mainStack, const [
        _Home(),
        _ProductList(),
        _ProductDetail('sku-1'),
      ]);
    });

    test('unmatched URL uses the fallback', () {
      expect(codec.decode(Uri.parse('/nope/x'))?.mainStack, const [
        _Home(),
        _NotFound('/nope/x'),
      ]);
    });
  });

  group('encode', () {
    final codec = _codec();

    test('encodes the stack leaf via the owning rule', () {
      expect(
        codec.encode(KaiselConfig(mainStack: const [_Home()])).toString(),
        '/',
      );
      expect(
        codec
            .encode(
              KaiselConfig(
                mainStack: const [_Home(), _ProductList(), _ProductDetail('z')],
              ),
            )
            .toString(),
        '/products/z',
      );
    });
  });

  group('round-trip self-check', () {
    test('passes for a complete, consistent codec', () {
      expect(
        () => _codec().debugAssertRoundTrips(const [
          _Home(),
          _ProductList(),
          _ProductDetail('abc'),
        ]),
        returnsNormally,
      );
    });

    test('throws when a custom rule breaks the round-trip', () {
      // encode sends every ProductDetail to /wrong, which decodes to Home —
      // exactly the encode/decode-drift bug, now caught at test time.
      final broken = RouteCodec<_App>(
        rules: [
          fixed(const _Home(), seg('wrong')),
          Rule<_App>.custom(
            decode: (uri) => null,
            encode: (config) => config.mainStack.last is _ProductDetail
                ? Uri(path: '/wrong')
                : null,
          ),
        ],
      );
      expect(
        () => broken.debugAssertRoundTrips(const [_ProductDetail('x')]),
        throwsStateError,
      );
    });
  });

  group('ordering disambiguates overlapping rules', () {
    test('a literal rule placed before a param rule wins for its URL', () {
      final codec = RouteCodec<_App>(
        rules: [
          fixed(const _ProductList(), seg('products') / seg('all')),
          (seg('products') / str)
              .to((c) => _ProductDetail(c.string(0)))
              .from((r) => r is _ProductDetail ? r.props : null),
        ],
      );
      expect(codec.decode(Uri.parse('/products/all'))?.mainStack, const [
        _ProductList(),
      ]);
      expect(codec.decode(Uri.parse('/products/sku'))?.mainStack, const [
        _ProductDetail('sku'),
      ]);
    });
  });
}
