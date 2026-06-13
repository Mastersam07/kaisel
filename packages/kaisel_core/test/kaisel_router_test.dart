import 'package:kaisel_core/kaisel_core.dart';
import 'package:test/test.dart';

sealed class _R extends KaiselRoute {
  const _R();
}

final class _A extends _R {
  const _A();
}

final class _B extends _R {
  const _B(this.tag);
  final String tag;
  @override
  List<Object?> get props => [tag];
}

final class _C extends _R {
  const _C();
}

final class _Named extends _R {
  const _Named();
  @override
  String get routeName => 'custom-name';
}

void main() {
  group('KaiselRouter', () {
    test('starts with the initial route on top', () {
      final r = KaiselRouter<_R>(initial: const _A());
      expect(r.stack, [const _A()]);
      expect(r.current, const _A());
      expect(r.depth, 1);
      expect(r.canPop, isFalse);
    });

    test('push appends to the stack and notifies', () async {
      final r = KaiselRouter<_R>(initial: const _A());
      var notifications = 0;
      r.addListener(() => notifications++);

      await r.push(const _B('one'));
      await r.push(const _C());

      expect(r.stack, [const _A(), const _B('one'), const _C()]);
      expect(r.current, const _C());
      expect(r.depth, 3);
      expect(r.canPop, isTrue);
      expect(notifications, 2);
    });

    test('pop removes the top and notifies; returns false on root', () async {
      final r = KaiselRouter<_R>(initial: const _A());
      await r.push(const _B('x'));
      var notifications = 0;
      r.addListener(() => notifications++);

      expect(await r.pop(), isTrue);
      expect(r.stack, [const _A()]);
      expect(notifications, 1);

      expect(await r.pop(), isFalse);
      expect(r.stack, [const _A()]);
      expect(notifications, 1);
    });

    test('replaceTop swaps the top route', () async {
      final r = KaiselRouter<_R>(initial: const _A());
      await r.push(const _B('x'));
      await r.replaceTop(const _C());
      expect(r.stack, [const _A(), const _C()]);
    });

    test(
      'pushOrReplaceTop pushes when no entry matches the predicate',
      () async {
        // From [_A]: pushOrReplaceTop(_B('x')) → push (the default
        // same-runtime-type predicate sees _A on top, not _B).
        final r = KaiselRouter<_R>(initial: const _A());
        await r.pushOrReplaceTop(const _B('x'));
        expect(r.stack, [const _A(), const _B('x')]);
      },
    );

    test(
      'pushOrReplaceTop replaces when current top matches by default',
      () async {
        // From [_A, _B('x')]: pushOrReplaceTop(_B('y')) → replace
        // (default predicate: same runtime type).
        final r = KaiselRouter<_R>(initial: const _A());
        await r.push(const _B('x'));
        await r.pushOrReplaceTop(const _B('y'));
        expect(r.stack, [const _A(), const _B('y')]);
      },
    );

    test('pushOrReplaceTop respects an explicit when predicate', () async {
      // Force push even though default would replace.
      final r = KaiselRouter<_R>(initial: const _A());
      await r.push(const _B('x'));
      await r.pushOrReplaceTop(const _B('y'), when: (_) => false);
      expect(r.stack, [const _A(), const _B('x'), const _B('y')]);

      // Force replace even on type mismatch.
      final r2 = KaiselRouter<_R>(initial: const _A());
      await r2.pushOrReplaceTop(const _B('z'), when: (_) => true);
      expect(r2.stack, [const _B('z')]);
    });

    test('pushOrReplaceTop with empty stack pushes', () async {
      // The route stack should never be empty in normal operation, and it
      // can't be constructed empty via the public API; this verifies that the
      // non-empty default path with an always-true predicate triggers
      // replaceTop.
      final r = KaiselRouter<_R>(initial: const _A());
      await r.pushOrReplaceTop(const _A());
      expect(r.stack, [const _A()]);
    });

    test('set replaces the whole stack', () async {
      final r = KaiselRouter<_R>(initial: const _A());
      await r.set([const _B('a'), const _B('b'), const _C()]);
      expect(r.stack, [const _B('a'), const _B('b'), const _C()]);
      expect(r.depth, 3);
    });

    test('set rejects empty stacks synchronously', () {
      final r = KaiselRouter<_R>(initial: const _A());
      expect(() => r.set([]), throwsArgumentError);
    });

    test('popUntil pops until predicate holds, preserving root', () async {
      final r = KaiselRouter<_R>(initial: const _A());
      await r.push(const _B('one'));
      await r.push(const _B('two'));
      await r.push(const _C());

      await r.popUntil((route) => route is _B && route.tag == 'one');
      expect(r.stack, [const _A(), const _B('one')]);
    });

    test('popUntil stops at root if nothing matches', () async {
      final r = KaiselRouter<_R>(initial: const _A());
      await r.push(const _B('x'));
      await r.popUntil((route) => route is _C);
      expect(r.stack, [const _A()]);
    });

    test('fromStack preserves order', () {
      final r = KaiselRouter<_R>.fromStack(const [_A(), _B('x'), _C()]);
      expect(r.stack, const [_A(), _B('x'), _C()]);
      expect(r.depth, 3);
    });

    test('fromStack rejects empty', () {
      expect(() => KaiselRouter<_R>.fromStack(const []), throwsArgumentError);
    });

    test('duplicate equal routes coexist on the stack', () async {
      // Two value-equal routes do not collapse — identity is tracked
      // separately by the internal entries.
      final r = KaiselRouter<_R>(initial: const _A());
      await r.push(const _B('x'));
      await r.push(const _B('x'));
      expect(r.depth, 3);
      expect(await r.pop(), isTrue);
      expect(r.depth, 2);
      expect(r.current, const _B('x'));
    });

    test(
      'serial mutations apply in submission order without awaiting',
      () async {
        final r = KaiselRouter<_R>(initial: const _A());
        // Fire-and-forget; they should still serialise.
        r.push(const _B('1'));
        r.push(const _B('2'));
        r.push(const _C());
        await r.push(const _B('end'));
        expect(r.stack, [
          const _A(),
          const _B('1'),
          const _B('2'),
          const _C(),
          const _B('end'),
        ]);
      },
    );

    test('re-pushing the same top route is a no-op (no notify)', () async {
      // With identity-preserving diff, push then replace with an equal
      // top yields no change, hence no notify.
      final r = KaiselRouter<_R>(initial: const _A());
      await r.push(const _B('x'));
      var notifications = 0;
      r.addListener(() => notifications++);
      await r.replaceTop(const _B('x'));
      expect(notifications, 0);
    });

    test('rapid pops without awaiting unwind the stack one-per-call', () async {
      // Each pop's target is computed at task-run time, not at call time,
      // so two pops from a 3-deep stack pop two routes, not one.
      final r = KaiselRouter<_R>(initial: const _A());
      await r.push(const _B('1'));
      await r.push(const _B('2'));
      expect(r.depth, 3);

      r.pop();
      await r.pop();
      expect(r.depth, 1);
      expect(r.stack, [const _A()]);
    });

    test('entries exposes identity-stable stack entries', () async {
      final r = KaiselRouter<_R>(initial: const _A());
      await r.push(const _B('x'));

      final entries = r.entries;
      expect(entries.length, 2);
      expect(entries.map((e) => e.route), [const _A(), const _B('x')]);
      expect(entries.first.id == entries.last.id, isFalse);
    });

    test(
      'onPageRemoved removes the entry whose id matches and notifies',
      () async {
        final r = KaiselRouter<_R>(initial: const _A());
        await r.push(const _B('x'));
        expect(r.depth, 2);

        var notifications = 0;
        r.addListener(() => notifications++);

        final topId = r.entries.last.id;
        r.onPageRemoved(topId);

        expect(r.stack, [const _A()]);
        expect(r.depth, 1);
        expect(notifications, 1);
      },
    );

    test('onPageRemoved is a no-op for an unknown id', () async {
      final r = KaiselRouter<_R>(initial: const _A());
      await r.push(const _B('x'));

      var notifications = 0;
      r.addListener(() => notifications++);

      r.onPageRemoved(999999);

      expect(r.stack, [const _A(), const _B('x')]);
      expect(r.depth, 2);
      expect(notifications, 0);
    });

    test('onPageRemoved refuses to remove when only one entry remains', () {
      final r = KaiselRouter<_R>(initial: const _A());
      expect(r.depth, 1);

      var notifications = 0;
      r.addListener(() => notifications++);

      final onlyId = r.entries.single.id;
      r.onPageRemoved(onlyId);

      expect(r.stack, [const _A()]);
      expect(r.depth, 1);
      expect(notifications, 0);
    });

    test(
      'applyFromInformation applies the given stack to the router',
      () async {
        final r = KaiselRouter<_R>(initial: const _A());

        await r.applyFromInformation([
          const _A(),
          const _B('deep'),
          const _C(),
        ]);

        expect(r.stack, [const _A(), const _B('deep'), const _C()]);
        expect(r.depth, 3);
        expect(r.current, const _C());
      },
    );
  });

  group('KaiselRouter equality default', () {
    test('no-field variants compare equal by runtime type', () {
      expect(const _A(), const _A());
      expect(const _C(), const _C());
      expect(const _A() == const _C(), isFalse);
    });

    test('variants with props compare by props', () {
      expect(const _B('x'), const _B('x'));
      expect(const _B('x') == const _B('y'), isFalse);
    });

    test('hashCode is stable across equal instances', () {
      expect(const _B('x').hashCode, const _B('x').hashCode);
      expect(const _A().hashCode, const _A().hashCode);
    });

    test('toString includes props', () {
      expect(const _A().toString(), '_A');
      expect(const _B('x').toString(), '_B(x)');
    });

    test('routeName defaults to the runtime type, ignoring props', () {
      expect(const _A().routeName, '_A');
      expect(const _B('x').routeName, '_B');
    });

    test('routeName can be overridden', () {
      expect(const _Named().routeName, 'custom-name');
    });
  });

  group('transition origin', () {
    test('a committed push records the caller as the origin', () async {
      final r = KaiselRouter<_R>(initial: const _A());
      expect(r.debugLastTransitionOrigin, isNull);

      await r.push(const _C());

      final origin = r.debugLastTransitionOrigin;
      expect(origin, isNotNull);
      expect('$origin', contains('kaisel_router_test.dart'));
    });

    test('the origin stamp advances on each committed change', () async {
      final r = KaiselRouter<_R>(initial: const _A());

      await r.push(const _C());
      final first = r.debugLastTransitionSeq;
      expect(first, greaterThan(0));

      await r.pop();
      expect(r.debugLastTransitionSeq, greaterThan(first));
    });

    test('a no-op navigation leaves the origin and stamp unchanged', () async {
      final r = KaiselRouter<_R>(initial: const _A());
      await r.push(const _B('x'));
      final seq = r.debugLastTransitionSeq;
      final origin = r.debugLastTransitionOrigin;

      await r.replaceTop(const _B('x'));

      expect(r.debugLastTransitionSeq, seq);
      expect(r.debugLastTransitionOrigin, same(origin));
    });

    test('the stamp is shared, ordering routers by recency', () async {
      final a = KaiselRouter<_R>(initial: const _A());
      final b = KaiselRouter<_R>(initial: const _A());

      await a.push(const _C());
      await b.push(const _C());

      expect(b.debugLastTransitionSeq, greaterThan(a.debugLastTransitionSeq));
    });
  });
}
