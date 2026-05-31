import 'package:flutter_test/flutter_test.dart';
import 'package:gate/gate.dart';

sealed class _R extends GateRoute {
  const _R();
}

final class _Home extends _R {
  const _Home();
}

final class _SecondStep extends _R {
  const _SecondStep(this.tag);
  final String tag;
  @override
  List<Object?> get props => [tag];
}

// A flow returning a String.
final class _StringFlow extends _R implements GateModalRoute<String> {
  const _StringFlow();
}

// A flow returning a bool.
final class _BoolFlow extends _R implements GateModalRoute<bool> {
  const _BoolFlow();
}

void main() {
  group('GateRouter.run / completeFlow', () {
    test('starts with no active flow', () {
      final r = GateRouter<_R>(initial: const _Home());
      expect(r.hasActiveFlow, isFalse);
      expect(r.activeFlowRoute, isNull);
      expect(r.activeFlowRouter, isNull);
    });

    test('run activates a sub-router and notifies', () async {
      final r = GateRouter<_R>(initial: const _Home());
      var notifications = 0;
      r.addListener(() => notifications++);

      final future = r.run(const _StringFlow());
      // Setup notifies once: state changed (flow became active).
      expect(notifications, 1);
      expect(r.hasActiveFlow, isTrue);
      expect(r.activeFlowRoute, isA<_StringFlow>());
      expect(r.activeFlowRouter, isNotNull);
      expect(r.activeFlowRouter!.stack, [const _StringFlow()]);

      r.completeFlow<String>('done');
      final result = await future;
      expect(result, 'done');
      expect(r.hasActiveFlow, isFalse);
      expect(r.activeFlowRoute, isNull);
      expect(r.activeFlowRouter, isNull);
    });

    test('dismissFlow resolves with null', () async {
      final r = GateRouter<_R>(initial: const _Home());
      final future = r.run(const _StringFlow());
      r.dismissFlow();
      final result = await future;
      expect(result, isNull);
      expect(r.hasActiveFlow, isFalse);
    });

    test('completeFlow with null also resolves with null', () async {
      final r = GateRouter<_R>(initial: const _Home());
      final future = r.run(const _BoolFlow());
      r.completeFlow<bool>(null);
      final result = await future;
      expect(result, isNull);
    });

    test('completeFlow with no active flow is a no-op', () {
      final r = GateRouter<_R>(initial: const _Home());
      // Should not throw.
      r.completeFlow<int>(42);
      r.dismissFlow();
      expect(r.hasActiveFlow, isFalse);
    });

    test('nested run throws StateError', () async {
      final r = GateRouter<_R>(initial: const _Home());
      final first = r.run(const _StringFlow());
      expect(
        () => r.run(const _BoolFlow()),
        throwsA(isA<StateError>()),
      );
      r.dismissFlow();
      await first;
    });

    test('flow returning incompatible route type throws ArgumentError',
        () async {
      // A modal route that's not part of the router's R hierarchy.
      // Constructed inline to bypass sealed enforcement at the test
      // boundary.
      final r = GateRouter<_R>(initial: const _Home());
      expect(
        () => r.run(const _ForeignFlow()),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('sub-router push/pop work within the flow', () async {
      final r = GateRouter<_R>(initial: const _Home());
      final future = r.run(const _StringFlow());
      final flow = r.activeFlowRouter!;

      await flow.push(const _SecondStep('a'));
      expect(flow.stack, [const _StringFlow(), const _SecondStep('a')]);
      expect(flow.depth, 2);

      await flow.pop();
      expect(flow.stack, [const _StringFlow()]);

      r.completeFlow<String>('ok');
      await future;
    });

    test('sub-router can take its own guards', () async {
      final guardCalls = <List<_R>>[];
      final r = GateRouter<_R>(initial: const _Home());
      final future = r.run(
        const _StringFlow(),
        flowGuards: [
          (current, proposed) {
            guardCalls.add(List.of(proposed));
            return proposed;
          },
        ],
      );
      final flow = r.activeFlowRouter!;
      await flow.push(const _SecondStep('x'));
      expect(guardCalls, hasLength(1));
      expect(guardCalls.single, [const _StringFlow(), const _SecondStep('x')]);
      r.dismissFlow();
      await future;
    });

    test('dispose resolves an in-flight flow with null', () async {
      final r = GateRouter<_R>(initial: const _Home());
      final future = r.run(const _StringFlow());
      r.dispose();
      final result = await future;
      expect(result, isNull);
    });

    test('completeFlow on a completed flow is a no-op', () async {
      final r = GateRouter<_R>(initial: const _Home());
      final future = r.run(const _StringFlow());
      r.completeFlow<String>('first');
      r.completeFlow<String>('second'); // ignored
      final result = await future;
      expect(result, 'first');
    });
  });
}

// A modal route NOT in the _R sealed hierarchy — used to test the
// runtime type check inside run<T>.
final class _ForeignFlow extends GateRoute implements GateModalRoute<String> {
  const _ForeignFlow();
}
