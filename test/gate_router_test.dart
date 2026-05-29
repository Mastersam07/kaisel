import 'package:flutter_test/flutter_test.dart';
import 'package:gate/gate.dart';

// Test fixtures: a tiny sealed route type using v0.2's default
// props-based equality. No manual == / hashCode needed.
sealed class _R extends GateRoute {
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

void main() {
  group('GateRouter', () {
    test('starts with the initial route on top', () {
      final r = GateRouter<_R>(initial: const _A());
      expect(r.stack, [const _A()]);
      expect(r.current, const _A());
      expect(r.depth, 1);
      expect(r.canPop, isFalse);
    });

    test('push appends to the stack and notifies', () async {
      final r = GateRouter<_R>(initial: const _A());
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

    test('pop removes the top and notifies; returns false on root',
        () async {
      final r = GateRouter<_R>(initial: const _A());
      await r.push(const _B('x'));
      var notifications = 0;
      r.addListener(() => notifications++);

      expect(await r.pop(), isTrue);
      expect(r.stack, [const _A()]);
      expect(notifications, 1);

      // Root: refuses to pop and does not notify.
      expect(await r.pop(), isFalse);
      expect(r.stack, [const _A()]);
      expect(notifications, 1);
    });

    test('replace swaps the top route', () async {
      final r = GateRouter<_R>(initial: const _A());
      await r.push(const _B('x'));
      await r.replace(const _C());
      expect(r.stack, [const _A(), const _C()]);
    });

    test('set replaces the whole stack', () async {
      final r = GateRouter<_R>(initial: const _A());
      await r.set([const _B('a'), const _B('b'), const _C()]);
      expect(r.stack, [const _B('a'), const _B('b'), const _C()]);
      expect(r.depth, 3);
    });

    test('set rejects empty stacks synchronously', () {
      final r = GateRouter<_R>(initial: const _A());
      expect(() => r.set([]), throwsArgumentError);
    });

    test('popUntil pops until predicate holds, preserving root', () async {
      final r = GateRouter<_R>(initial: const _A());
      await r.push(const _B('one'));
      await r.push(const _B('two'));
      await r.push(const _C());

      await r.popUntil((route) => route is _B && route.tag == 'one');
      expect(r.stack, [const _A(), const _B('one')]);
    });

    test('popUntil stops at root if nothing matches', () async {
      final r = GateRouter<_R>(initial: const _A());
      await r.push(const _B('x'));
      await r.popUntil((route) => route is _C);
      expect(r.stack, [const _A()]);
    });

    test('fromStack preserves order', () {
      final r = GateRouter<_R>.fromStack(const [_A(), _B('x'), _C()]);
      expect(r.stack, const [_A(), _B('x'), _C()]);
      expect(r.depth, 3);
    });

    test('fromStack rejects empty', () {
      expect(GateRouter<_R>.fromStack, throwsArgumentError);
    });

    test('duplicate equal routes coexist on the stack', () async {
      // Two value-equal routes do not collapse — identity is tracked
      // separately by the internal entries.
      final r = GateRouter<_R>(initial: const _A());
      await r.push(const _B('x'));
      await r.push(const _B('x'));
      expect(r.depth, 3);
      expect(await r.pop(), isTrue);
      expect(r.depth, 2);
      expect(r.current, const _B('x'));
    });

    test('serial mutations apply in submission order without awaiting',
        () async {
      final r = GateRouter<_R>(initial: const _A());
      // Fire-and-forget; they should still serialise.
      r.push(const _B('1'));
      r.push(const _B('2'));
      r.push(const _C());
      // Await the final operation to flush the queue.
      await r.push(const _B('end'));
      expect(r.stack, [
        const _A(),
        const _B('1'),
        const _B('2'),
        const _C(),
        const _B('end'),
      ]);
    });

    test('re-pushing the same top route is a no-op (no notify)', () async {
      // With identity-preserving diff, push then replace with an equal
      // top yields no change, hence no notify.
      final r = GateRouter<_R>(initial: const _A());
      await r.push(const _B('x'));
      var notifications = 0;
      r.addListener(() => notifications++);
      await r.replace(const _B('x'));
      expect(notifications, 0);
    });

    test('rapid pops without awaiting unwind the stack one-per-call',
        () async {
      // Each pop's target is computed at task-run time, not at call time,
      // so two pops from a 3-deep stack pop two routes, not one.
      final r = GateRouter<_R>(initial: const _A());
      await r.push(const _B('1'));
      await r.push(const _B('2'));
      expect(r.depth, 3);

      r.pop();
      await r.pop();
      expect(r.depth, 1);
      expect(r.stack, [const _A()]);
    });
  });

  group('GateRouter equality default', () {
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
  });
}
