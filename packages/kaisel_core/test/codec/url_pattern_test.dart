import 'package:kaisel_core/codec.dart';
import 'package:test/test.dart';

enum _Tab { home, matches, chat }

void main() {
  group('path (root / empty)', () {
    test('matches the index path and round-trips to /', () {
      expect(path.parseUri(Uri.parse('/')), ());
      expect(path.printUri(()).toString(), '/');
    });

    test('does not match a non-empty path', () {
      expect(path.parseUri(Uri.parse('/home')), isNull);
    });
  });

  group('literal segments', () {
    test('match and round-trip, capturing nothing', () {
      final p = path.seg('settings').seg('account');
      expect(p.parseUri(Uri.parse('/settings/account')), ());
      expect(p.printUri(()).toString(), '/settings/account');
    });

    test('reject a different segment and trailing segments', () {
      final p = path.seg('home');
      expect(p.parseUri(Uri.parse('/away')), isNull);
      expect(p.parseUri(Uri.parse('/home/extra')), isNull);
      expect(p.parseUri(Uri.parse('/')), isNull);
    });
  });

  group('params', () {
    test('str captures a String', () {
      final p = path.seg('products').param(str);
      final caps = p.parseUri(Uri.parse('/products/sku-9'));
      expect(caps, ('sku-9',));
      expect(caps?.$1, 'sku-9'); // typed access
      expect(p.printUri(('sku-9',)).toString(), '/products/sku-9');
    });

    test('intg captures an int and rejects non-ints', () {
      final p = path.seg('page').param(intg);
      expect(p.parseUri(Uri.parse('/page/42'))?.$1, 42);
      expect(p.parseUri(Uri.parse('/page/x')), isNull);
    });

    test('boolg captures a bool', () {
      final p = path.param(boolg);
      expect(p.parseUri(Uri.parse('/true')), (true,));
      expect(p.parseUri(Uri.parse('/yes')), isNull);
    });

    test('enumParam captures by name', () {
      final p = path.seg('tab').param(enumParam(_Tab.values));
      expect(p.parseUri(Uri.parse('/tab/matches'))?.$1, _Tab.matches);
      expect(p.printUri((_Tab.chat,)).toString(), '/tab/chat');
      expect(p.parseUri(Uri.parse('/tab/nope')), isNull);
    });
  });

  group('multi-param, typed flat captures', () {
    test('two params capture a typed (A, B) in order', () {
      final p = path.seg('chat').param(str).param(intg);
      final caps = p.parseUri(Uri.parse('/chat/room/5'));
      expect(caps, ('room', 5));
      expect(caps?.$1, 'room');
      expect(caps?.$2, 5);
      expect(p.printUri(('room', 5)).toString(), '/chat/room/5');
    });

    test('three params interleaved with literals', () {
      final p = path.seg('a').param(str).seg('b').param(intg).param(boolg);
      final caps = p.parseUri(Uri.parse('/a/x/b/9/true'));
      expect(caps, ('x', 9, true));
      expect(caps?.$3, true);
      expect(p.printUri(('x', 9, true)).toString(), '/a/x/b/9/true');
    });

    test('four params (the cap)', () {
      final p = path.param(str).param(intg).param(boolg).param(str);
      expect(p.parseUri(Uri.parse('/a/1/false/b')), ('a', 1, false, 'b'));
    });
  });

  group('no-match rolls back', () {
    test('a later mismatch yields null, leaving no partial capture', () {
      final p = path.seg('chat').param(str).param(intg);
      expect(p.parseUri(Uri.parse('/chat/room/notint')), isNull);
      expect(p.parseUri(Uri.parse('/chat/room')), isNull); // too short
    });
  });

  group('query params', () {
    test('required: captures when present, no match when absent', () {
      final p = path.seg('search').query(queryStr('q'));
      expect(p.parseUri(Uri.parse('/search?q=shoes')), ('shoes',));
      expect(p.parseUri(Uri.parse('/search')), isNull); // required, absent
      expect(p.printUri(('shoes',)).toString(), '/search?q=shoes');
    });

    test('optional: null when absent, value when present, always matches', () {
      final p = path.seg('search').query(queryStrOpt('city'));
      expect(p.parseUri(Uri.parse('/search')), (null,));
      expect(p.parseUri(Uri.parse('/search?city=NYC')), ('NYC',));
      expect(p.printUri((null,)).toString(), '/search'); // omitted when null
      expect(p.printUri(('NYC',)).toString(), '/search?city=NYC');
    });

    test('orElse: absent reads as default; default value omits the key', () {
      final p = path.seg('list').query(queryInt('page', orElse: 1));
      expect(p.parseUri(Uri.parse('/list')), (1,)); // absent → default
      expect(p.parseUri(Uri.parse('/list?page=3')), (3,));
      expect(p.printUri((1,)).toString(), '/list'); // default omitted
      expect(p.printUri((3,)).toString(), '/list?page=3');
    });

    test('path + multiple query params capture in order', () {
      final p = path
          .seg('search')
          .query(queryStr('q'))
          .query(queryInt('page', orElse: 1));
      final caps = p.parseUri(Uri.parse('/search?q=shoes&page=2'));
      expect(caps, ('shoes', 2));
      expect(caps?.$1, 'shoes');
      expect(caps?.$2, 2);
    });

    test('query does not consume path segments', () {
      final p = path.seg('search').query(queryStrOpt('q'));
      expect(p.parseUri(Uri.parse('/search/extra')), isNull); // trailing path
    });
  });

  group('round-trip property', () {
    test('parse(print(x)) == x for path + query', () {
      final p = path
          .seg('chat')
          .param(str)
          .param(intg)
          .query(queryStr('q'))
          .query(queryInt('page', orElse: 1));
      const x = ('room', 5, 'hi', 3);
      expect(p.parseUri(p.printUri(x)), x);
    });
  });
}
