import 'package:kaisel_core/kaisel_core.dart';
import 'package:test/test.dart';

sealed class _R extends KaiselRoute {
  const _R();
}

final class _Home extends _R {
  const _Home();
}

final class _Detail extends _R {
  const _Detail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

class _StackCodec implements KaiselStackCodec<_R> {
  const _StackCodec();

  @override
  Uri encode(List<_R> stack) => switch (stack.last) {
    _Home() => Uri(path: '/'),
    _Detail(:final id) => Uri(path: '/d/$id'),
  };

  @override
  List<_R>? decode(Uri uri) => switch (uri.pathSegments) {
    [] || [''] => const [_Home()],
    ['d', final id] => [const _Home(), _Detail(id)],
    _ => null,
  };
}

class _SingleCodec implements KaiselCodec<_R> {
  const _SingleCodec();

  @override
  Uri encode(_R route) => switch (route) {
    _Home() => Uri(path: '/'),
    _Detail(:final id) => Uri(path: '/d/$id'),
  };

  @override
  _R? decode(Uri uri) => switch (uri.pathSegments) {
    [] || [''] => const _Home(),
    ['d', final id] => _Detail(id),
    _ => null,
  };
}

void main() {
  group('KaiselStackCodec (concrete multi-frame)', () {
    const codec = _StackCodec();

    test('round-trips a single-frame stack', () {
      const stack = [_Home()];
      expect(codec.decode(codec.encode(stack)), stack);
    });

    test('round-trips a deep-linked multi-frame stack', () {
      const stack = [_Home(), _Detail('42')];
      final encoded = codec.encode(stack);
      expect(encoded.path, '/d/42');
      // decode restores the implicit parent frame too.
      expect(codec.decode(encoded), stack);
    });

    test('round-trips preserving route props', () {
      const stack = [_Home(), _Detail('abc-123')];
      final decoded = codec.decode(codec.encode(stack));
      expect(decoded, stack);
      expect(decoded?.last, const _Detail('abc-123'));
    });

    test('decode returns null for an unknown URI', () {
      expect(codec.decode(Uri(path: '/totally/unknown')), isNull);
    });
  });

  group('KaiselSingleStackCodec (adapter over KaiselCodec)', () {
    const inner = _SingleCodec();
    const codec = KaiselSingleStackCodec<_R>(inner);

    test('encode delegates to inner codec on the top of the stack', () {
      const stack = [_Home(), _Detail('x')];
      expect(codec.encode(stack), inner.encode(const _Detail('x')));
      expect(codec.encode(stack).path, '/d/x');
    });

    test('decode wraps the inner route in a depth-1 stack', () {
      final decoded = codec.decode(Uri(path: '/d/7'));
      expect(decoded, const [_Detail('7')]);
      expect(decoded?.length, 1);
    });

    test('decode of root yields a depth-1 home stack', () {
      expect(codec.decode(Uri(path: '/')), const [_Home()]);
    });

    test('decode returns null when the inner codec returns null', () {
      expect(inner.decode(Uri(path: '/nope')), isNull);
      expect(codec.decode(Uri(path: '/nope')), isNull);
    });

    test('round-trips the top route through the adapter', () {
      const stack = [_Home(), _Detail('rt')];
      final decoded = codec.decode(codec.encode(stack));
      // Adapter collapses to depth-1, keeping the top route.
      expect(decoded, const [_Detail('rt')]);
    });

    test('constructs at runtime (exercises the const constructor)', () {
      T rt<T>(T v) => v; // passthrough: forces a runtime (non-const) build

      final runtime = KaiselSingleStackCodec<_R>(rt(const _SingleCodec()));
      expect(runtime.decode(Uri(path: '/')), const [_Home()]);
    });
  });

  test('KaiselStackCodec can be extended, not just implemented', () {
    final codec = _ExtStackCodec();
    expect(codec.encode(const [_Home()]).path, '/x');
    expect(codec.decode(Uri(path: '/y')), isNull);
  });

  test('StackToConfigCodec wraps a stack codec at runtime', () {
    final codec = StackToConfigCodec<_R>(_ExtStackCodec());
    expect(codec.stackCodec, isA<KaiselStackCodec<_R>>());
  });
}

// Extends (not implements) KaiselStackCodec, exercising its const constructor.
class _ExtStackCodec extends KaiselStackCodec<_R> {
  _ExtStackCodec();

  @override
  Uri encode(List<_R> stack) => Uri(path: '/x');

  @override
  List<_R>? decode(Uri uri) => null;
}
