import 'package:kaisel_core/codec.dart';
import 'package:test/test.dart';

enum _Tab { home, matches, chat }

void main() {
  group('root', () {
    test('matches the empty path and prints to /', () {
      expect(root.parseUri(Uri.parse('/')), <Object?>[]);
      expect(root.printUri(const <Object?>[]).toString(), '/');
    });

    test('does not match a non-empty path', () {
      expect(root.parseUri(Uri.parse('/home')), isNull);
    });
  });

  group('path leaves', () {
    test('seg matches its literal, capturing nothing', () {
      expect(seg('home').parseUri(Uri.parse('/home')), <Object?>[]);
      expect(seg('home').parseUri(Uri.parse('/away')), isNull);
      expect(seg('home').parseUri(Uri.parse('/home/extra')), isNull);
    });

    test('str captures one segment', () {
      expect(str.parseUri(Uri.parse('/abc')), <Object?>['abc']);
      expect(str.parseUri(Uri.parse('/a/b')), isNull);
    });

    test('intg parses/prints an int and rejects non-ints', () {
      expect(intg.parseUri(Uri.parse('/42')), <Object?>[42]);
      expect(intg.printUri(const <Object?>[42]).toString(), '/42');
      expect(intg.parseUri(Uri.parse('/x')), isNull);
    });

    test('boolg parses true/false', () {
      expect(boolg.parseUri(Uri.parse('/true')), <Object?>[true]);
      expect(boolg.parseUri(Uri.parse('/yes')), isNull);
    });

    test('enumOf matches by name', () {
      final tab = enumOf(_Tab.values);
      expect(tab.parseUri(Uri.parse('/matches')), <Object?>[_Tab.matches]);
      expect(tab.printUri(const <Object?>[_Tab.chat]).toString(), '/chat');
      expect(tab.parseUri(Uri.parse('/nope')), isNull);
    });
  });

  group('composition with / (any arity, no per-arity classes)', () {
    test('literal then param', () {
      final p = seg('products') / str;
      expect(p.parseUri(Uri.parse('/products/sku-9')), <Object?>['sku-9']);
      expect(
        p.printUri(const <Object?>['sku-9']).toString(),
        '/products/sku-9',
      );
    });

    test('many params capture in order — well past any builder cap', () {
      final p = seg('a') / str / intg / boolg / str / intg / str;
      final caps = p.parseUri(Uri.parse('/a/x/1/true/y/2/z'));
      expect(caps, <Object?>['x', 1, true, 'y', 2, 'z']);
      expect(
        p.printUri(caps ?? const <Object?>[]).toString(),
        '/a/x/1/true/y/2/z',
      );
    });

    test('a later mismatch rolls back to null, no partial captures', () {
      final p = seg('chat') / str / intg;
      expect(p.parseUri(Uri.parse('/chat/room/notint')), isNull);
      expect(p.parseUri(Uri.parse('/chat/room')), isNull);
    });

    test('flattens — nested chaining stays a single sequence', () {
      final p = (seg('a') / str) / (seg('b') / intg);
      expect(p.parseUri(Uri.parse('/a/x/b/7')), <Object?>['x', 7]);
    });
  });

  group('query params (composable patterns)', () {
    test('required: captures when present, no match when absent', () {
      final p = seg('search') / queryStr('q');
      expect(p.parseUri(Uri.parse('/search?q=shoes')), <Object?>['shoes']);
      expect(p.parseUri(Uri.parse('/search')), isNull);
      expect(
        p.printUri(const <Object?>['shoes']).toString(),
        '/search?q=shoes',
      );
    });

    test(
      'optional: null when absent, value when present, omitted on write',
      () {
        final p = seg('search') / queryStrOpt('city');
        expect(p.parseUri(Uri.parse('/search')), <Object?>[null]);
        expect(p.parseUri(Uri.parse('/search?city=NYC')), <Object?>['NYC']);
        expect(p.printUri(const <Object?>[null]).toString(), '/search');
        expect(
          p.printUri(const <Object?>['NYC']).toString(),
          '/search?city=NYC',
        );
      },
    );

    test('orElse: absent reads as default; default value omits the key', () {
      final p = seg('list') / queryInt('page', orElse: 1);
      expect(p.parseUri(Uri.parse('/list')), <Object?>[1]);
      expect(p.parseUri(Uri.parse('/list?page=3')), <Object?>[3]);
      expect(p.printUri(const <Object?>[1]).toString(), '/list');
      expect(p.printUri(const <Object?>[3]).toString(), '/list?page=3');
    });

    test('path + multiple query params capture in order', () {
      final p = seg('search') / queryStr('q') / queryInt('page', orElse: 1);
      expect(p.parseUri(Uri.parse('/search?q=shoes&page=2')), <Object?>[
        'shoes',
        2,
      ]);
    });

    test('query does not consume path segments', () {
      final p = seg('search') / queryStrOpt('q');
      expect(p.parseUri(Uri.parse('/search/extra')), isNull);
    });
  });

  group('Captures accessors', () {
    test('typed positional access, including nullable', () {
      const c = Captures(<Object?>['room', 5, true, _Tab.chat, null]);
      expect(c.string(0), 'room');
      expect(c.integer(1), 5);
      expect(c.boolean(2), isTrue);
      expect(c.enumValue<_Tab>(3), _Tab.chat);
      expect(c.stringOrNull(4), isNull);
      expect(c[0], 'room');
      expect(c.length, 5);
    });
  });

  group('round-trip property', () {
    test('parse(print(x)) == x for path + query', () {
      final p =
          seg('chat') /
          str /
          intg /
          queryStr('q') /
          queryInt('page', orElse: 1);
      final x = <Object?>['room', 5, 'hi', 3];
      expect(p.parseUri(p.printUri(x)), x);
    });
  });
}
