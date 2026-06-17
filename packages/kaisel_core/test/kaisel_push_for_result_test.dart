import 'package:kaisel_core/kaisel_core.dart';
import 'package:kaisel_core/framework.dart';
import 'package:test/test.dart';

sealed class _R extends KaiselRoute {
  const _R();
}

final class _Home extends _R {
  const _Home();
}

final class _Picker extends _R {
  const _Picker();
}

final class _Other extends _R {
  const _Other();
}

void main() {
  group('pushForResult', () {
    test('resolves with the value passed to pop(result)', () async {
      final r = KaiselRouter<_R>(initial: const _Home());

      final future = r.pushForResult<String>(const _Picker());
      // The screen is on the main stack, not a separate flow.
      await Future<void>.delayed(Duration.zero);
      expect(r.stack, [const _Home(), const _Picker()]);
      expect(r.hasActiveFlow, isFalse);

      await r.pop('chosen');
      expect(await future, 'chosen');
      expect(r.stack, [const _Home()]);
    });

    test('resolves with null when popped without a value', () async {
      final r = KaiselRouter<_R>(initial: const _Home());
      final future = r.pushForResult<String>(const _Picker());
      await r.pop();
      expect(await future, isNull);
    });

    test('resolves with null when replaced off the stack by set', () async {
      final r = KaiselRouter<_R>(initial: const _Home());
      final future = r.pushForResult<String>(const _Picker());
      await Future<void>.delayed(Duration.zero);
      await r.set([const _Home(), const _Other()]);
      expect(await future, isNull);
    });

    test('resolves with null when replaceTop replaces it', () async {
      final r = KaiselRouter<_R>(initial: const _Home());
      final future = r.pushForResult<String>(const _Picker());
      await Future<void>.delayed(Duration.zero);
      await r.replaceTop(const _Other());
      expect(await future, isNull);
    });

    test('resolves with null on a Navigator-driven removal', () async {
      final r = KaiselRouter<_R>(initial: const _Home());
      final future = r.pushForResult<String>(const _Picker());
      await Future<void>.delayed(Duration.zero);
      // Simulate a system-back pop the delegate forwards.
      final pickerId = r.entries.last.id;
      r.onPageRemoved(pickerId);
      expect(await future, isNull);
    });

    test(
      'a stashed result is delivered through a Navigator-driven removal',
      () async {
        final r = KaiselRouter<_R>(initial: const _Home());
        final future = r.pushForResult<int>(const _Picker());
        await Future<void>.delayed(Duration.zero);
        final pickerId = r.entries.last.id;
        r.stashResult(42);
        r.onPageRemoved(pickerId);
        expect(await future, 42);
      },
    );

    test('resolves with null on dispose so awaiters do not hang', () async {
      final r = KaiselRouter<_R>(initial: const _Home());
      final future = r.pushForResult<String>(const _Picker());
      await Future<void>.delayed(Duration.zero);
      r.dispose();
      expect(await future, isNull);
    });

    test('resolves with null when a guard prevents it from landing', () async {
      // A guard that refuses to let _Picker onto the stack.
      List<_R> noPicker(List<_R> current, List<_R> proposed) =>
          proposed.where((route) => route is! _Picker).toList();
      final r = KaiselRouter<_R>(initial: const _Home(), guards: [noPicker]);

      final result = await r.pushForResult<String>(const _Picker());
      expect(result, isNull);
      expect(r.stack, [const _Home()]);
    });

    test('nested pushes resolve independently in LIFO order', () async {
      final r = KaiselRouter<_R>(initial: const _Home());

      final first = r.pushForResult<String>(const _Picker());
      await Future<void>.delayed(Duration.zero);
      final second = r.pushForResult<String>(const _Other());
      await Future<void>.delayed(Duration.zero);
      expect(r.stack, [const _Home(), const _Picker(), const _Other()]);

      await r.pop('second-result');
      expect(await second, 'second-result');

      await r.pop('first-result');
      expect(await first, 'first-result');
    });

    test('a plain push still settles on navigation, not on pop', () async {
      final r = KaiselRouter<_R>(initial: const _Home());
      // push resolves once applied; it must not wait for a pop.
      await r.push(const _Picker()).timeout(const Duration(seconds: 1));
      expect(r.stack, [const _Home(), const _Picker()]);
    });
  });
}
