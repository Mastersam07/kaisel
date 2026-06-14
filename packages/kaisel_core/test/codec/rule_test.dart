import 'package:kaisel_core/codec.dart';
import 'package:kaisel_core/kaisel_core.dart';
import 'package:test/test.dart';

sealed class _App extends KaiselRoute {
  const _App();
}

final class _Home extends _App {
  const _Home();
}

final class _ProductDetail extends _App {
  const _ProductDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

final class _Order extends _App {
  const _Order(this.id, this.page);
  final String id;
  final int page;
  @override
  List<Object?> get props => [id, page];
}

KaiselConfig<_App> _cfg(List<_App> stack) => KaiselConfig(mainStack: stack);

void main() {
  group('fixed', () {
    final Rule<_App> rule = fixed(const _Home(), root);

    test('decodes / to [Home] and encodes Home to /', () {
      expect(rule.decode(Uri.parse('/'))?.mainStack, const [_Home()]);
      expect(rule.encode(_cfg(const [_Home()]))?.toString(), '/');
    });

    test('does not own a different route or a different url', () {
      expect(rule.encode(_cfg(const [_ProductDetail('x')])), isNull);
      expect(rule.decode(Uri.parse('/products/x')), isNull);
    });
  });

  group('.to().from()', () {
    final Rule<_App> rule = (seg('products') / str)
        .to((c) => _ProductDetail(c.string(0)))
        .from((r) => r is _ProductDetail ? r.props : null);

    test('decodes a single-param url to the leaf', () {
      expect(rule.decode(Uri.parse('/products/sku-9'))?.mainStack, const [
        _ProductDetail('sku-9'),
      ]);
    });

    test('encodes via props', () {
      expect(
        rule.encode(_cfg(const [_ProductDetail('sku-9')]))?.toString(),
        '/products/sku-9',
      );
    });

    test('does not own another route type', () {
      expect(rule.encode(_cfg(const [_Home()])), isNull);
    });
  });

  group('multi-param via props order', () {
    final Rule<_App> rule = (seg('orders') / str / intg)
        .to((c) => _Order(c.string(0), c.integer(1)))
        .from((r) => r is _Order ? r.props : null);

    test('round-trips two captures in props order', () {
      const route = _Order('o-1', 3);
      expect(rule.decode(Uri.parse('/orders/o-1/3'))?.mainStack, const [route]);
      expect(rule.encode(_cfg(const [route]))?.toString(), '/orders/o-1/3');
    });
  });

  group('.under() breadcrumb', () {
    final Rule<_App> rule = (seg('products') / str)
        .to((c) => _ProductDetail(c.string(0)))
        .under(const [_Home()])
        .from((r) => r is _ProductDetail ? r.props : null);

    test('decodes onto the breadcrumb; encode still keys on the leaf', () {
      expect(rule.decode(Uri.parse('/products/x'))?.mainStack, const [
        _Home(),
        _ProductDetail('x'),
      ]);
      expect(
        rule.encode(_cfg(const [_ProductDetail('x')]))?.toString(),
        '/products/x',
      );
    });
  });

  group('.from() explicit matcher', () {
    final Rule<_App> rule = (seg('p') / str)
        .to((c) => _ProductDetail(c.string(0)))
        .from((r) => r is _ProductDetail ? [r.id] : null);

    test('round-trips', () {
      expect(rule.decode(Uri.parse('/p/z'))?.mainStack, const [
        _ProductDetail('z'),
      ]);
      expect(
        rule.encode(_cfg(const [_ProductDetail('z')]))?.toString(),
        '/p/z',
      );
    });
  });

  group('Rule.custom', () {
    final Rule<_App> rule = Rule<_App>.custom(
      decode: (uri) => uri.path == '/legacy' ? _cfg(const [_Home()]) : null,
      encode: (config) => null,
    );

    test('uses the hand-written directions', () {
      expect(rule.decode(Uri.parse('/legacy'))?.mainStack, const [_Home()]);
      expect(rule.decode(Uri.parse('/other')), isNull);
      expect(rule.encode(_cfg(const [_Home()])), isNull);
    });
  });
}
