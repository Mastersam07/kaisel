import 'package:flutter_test/flutter_test.dart';
import 'package:gate/gate.dart';

// Test fixtures: a tiny sealed route type.
sealed class _R extends GateRoute {
  const _R();
}

final class _A extends _R {
  const _A();
  @override
  bool operator ==(Object other) => other is _A;
  @override
  int get hashCode => 0;
}

final class _B extends _R {
  const _B(this.tag);
  final String tag;
  @override
  bool operator ==(Object other) => other is _B && other.tag == tag;
  @override
  int get hashCode => tag.hashCode;
}

final class _C extends _R {
  const _C();
  @override
  bool operator ==(Object other) => other is _C;
  @override
  int get hashCode => 1;
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

    test('push appends to the stack and notifies', () {
      final r = GateRouter<_R>(initial: const _A());
      var notifications = 0;
      r.addListener(() => notifications++);

      r.push(const _B('one'));
      r.push(const _C());

      expect(r.stack, [const _A(), const _B('one'), const _C()]);
      expect(r.current, const _C());
      expect(r.depth, 3);
      expect(r.canPop, isTrue);
      expect(notifications, 2);
    });

    test('pop removes the top and notifies; returns false on root', () {
      final r = GateRouter<_R>(initial: const _A())..push(const _B('x'));
      var notifications = 0;
      r.addListener(() => notifications++);

      expect(r.pop(), isTrue);
      expect(r.stack, [const _A()]);
      expect(notifications, 1);

      // Root: refuses to pop and does not notify.
      expect(r.pop(), isFalse);
      expect(r.stack, [const _A()]);
      expect(notifications, 1);
    });

    test('replace swaps the top route', () {
      final r = GateRouter<_R>(initial: const _A())..push(const _B('x'));
      r.replace(const _C());
      expect(r.stack, [const _A(), const _C()]);
    });

    test('set replaces the whole stack', () {
      final r = GateRouter<_R>(initial: const _A());
      r.set([const _B('a'), const _B('b'), const _C()]);
      expect(r.stack, [const _B('a'), const _B('b'), const _C()]);
      expect(r.depth, 3);
    });

    test('set rejects empty stacks', () {
      final r = GateRouter<_R>(initial: const _A());
      expect(() => r.set([]), throwsArgumentError);
    });

    test('popUntil pops until predicate holds, preserving root', () {
      final r = GateRouter<_R>(initial: const _A())
        ..push(const _B('one'))
        ..push(const _B('two'))
        ..push(const _C());

      r.popUntil((route) => route is _B && route.tag == 'one');
      expect(r.stack, [const _A(), const _B('one')]);
    });

    test('popUntil stops at root if nothing matches', () {
      final r = GateRouter<_R>(initial: const _A())
        ..push(const _B('x'));
      r.popUntil((route) => route is _C);
      expect(r.stack, [const _A()]); // never pops the root
    });

    test('fromStack preserves order', () {
      final r = GateRouter<_R>.fromStack(const [_A(), _B('x'), _C()]);
      expect(r.stack, const [_A(), _B('x'), _C()]);
      expect(r.depth, 3);
    });

    test('fromStack rejects empty', () {
      expect(GateRouter<_R>.fromStack, throwsArgumentError);
    });

    test('duplicate equal routes coexist on the stack', () {
      // The router uses identity-stable entries internally, so two
      // value-equal routes do not collapse.
      final r = GateRouter<_R>(initial: const _A())
        ..push(const _B('x'))
        ..push(const _B('x'));
      expect(r.depth, 3);
      expect(r.pop(), isTrue);
      expect(r.depth, 2);
      expect(r.current, const _B('x'));
    });
  });
}
