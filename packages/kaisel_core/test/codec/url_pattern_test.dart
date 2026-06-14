import 'package:kaisel_core/codec.dart';
import 'package:test/test.dart';

enum _Tab { home, matches, chat }

void main() {
  group('root', () {
    test('matches the empty path and prints to /', () {
      expect(root.parseUri(Uri.parse('/')), ());
      expect(root.printUri(()).toString(), '/');
    });

    test('does not match a non-empty path', () {
      expect(root.parseUri(Uri.parse('/home')), isNull);
    });
  });

  group('seg', () {
    test('matches its literal and round-trips', () {
      expect(seg('home').parseUri(Uri.parse('/home')), ());
      expect(seg('home').printUri(()).toString(), '/home');
    });

    test('rejects a different segment, the empty path, and trailing segments', () {
      expect(seg('home').parseUri(Uri.parse('/away')), isNull);
      expect(seg('home').parseUri(Uri.parse('/')), isNull);
      expect(seg('home').parseUri(Uri.parse('/home/extra')), isNull);
    });
  });

  group('str', () {
    test('captures one segment and round-trips', () {
      expect(str.parseUri(Uri.parse('/abc')), ('abc',));
      expect(str.printUri(('abc',)).toString(), '/abc');
    });

    test('rejects the empty path and trailing segments', () {
      expect(str.parseUri(Uri.parse('/')), isNull);
      expect(str.parseUri(Uri.parse('/a/b')), isNull);
    });
  });

  group('intg', () {
    test('parses and prints an int', () {
      expect(intg.parseUri(Uri.parse('/42')), (42,));
      expect(intg.printUri((42,)).toString(), '/42');
    });

    test('does not match a non-int', () {
      expect(intg.parseUri(Uri.parse('/x')), isNull);
    });
  });

  group('boolg', () {
    test('parses and prints true/false', () {
      expect(boolg.parseUri(Uri.parse('/true')), (true,));
      expect(boolg.parseUri(Uri.parse('/false')), (false,));
      expect(boolg.printUri((true,)).toString(), '/true');
    });

    test('does not match a non-bool', () {
      expect(boolg.parseUri(Uri.parse('/yes')), isNull);
    });
  });

  group('enumOf', () {
    final tab = enumOf(_Tab.values);

    test('matches a value by name and round-trips', () {
      expect(tab.parseUri(Uri.parse('/matches')), (_Tab.matches,));
      expect(tab.printUri((_Tab.chat,)).toString(), '/chat');
    });

    test('does not match an unknown name', () {
      expect(tab.parseUri(Uri.parse('/profile')), isNull);
    });
  });

  group('round-trip property (leaves)', () {
    test('parse(print(x)) == x for every leaf', () {
      expect(root.parseUri(root.printUri(())), ());
      expect(seg('x').parseUri(seg('x').printUri(())), ());
      expect(str.parseUri(str.printUri(('hello',))), ('hello',));
      expect(intg.parseUri(intg.printUri((7,))), (7,));
      expect(boolg.parseUri(boolg.printUri((false,))), (false,));
      final tab = enumOf(_Tab.values);
      expect(tab.parseUri(tab.printUri((_Tab.home,))), (_Tab.home,));
    });
  });
}
