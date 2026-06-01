import 'package:gate_core/gate_core.dart';
import 'package:test/test.dart';

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
      expect(r.activeFlows, isEmpty);
    });

    test('run activates a sub-router and notifies', () async {
      final r = GateRouter<_R>(initial: const _Home());
      var notifications = 0;
      r.addListener(() => notifications++);

      final future = r.run(const _StringFlow());
      // Setup notifies once: state changed (flow became active).
      expect(notifications, 1);
      expect(r.hasActiveFlow, isTrue);
      expect(r.activeFlows.last.route, isA<_StringFlow>());
      expect(r.activeFlows, isNotEmpty);
      expect(r.activeFlows.last.router.stack, [const _StringFlow()]);

      r.completeFlow<String>('done');
      final result = await future;
      expect(result, 'done');
      expect(r.hasActiveFlow, isFalse);
      expect(r.activeFlows, isEmpty);
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

    test('nested run pushes the new flow onto the active stack', () async {
      final r = GateRouter<_R>(initial: const _Home());

      final first = r.run<String>(const _StringFlow());
      expect(r.activeFlows.length, 1);

      final second = r.run<bool>(const _BoolFlow());
      expect(r.activeFlows.length, 2);
      expect(r.activeFlows.last.route, isA<_BoolFlow>()); // topmost
      expect(r.activeFlows.first.route, isA<_StringFlow>());

      // Complete the inner flow first. The outer flow remains active.
      r.completeFlow<bool>(true);
      expect(await second, isTrue);
      expect(r.activeFlows.length, 1);
      expect(r.activeFlows.last.route, isA<_StringFlow>());

      // Now complete the outer flow.
      r.completeFlow<String>('done');
      expect(await first, 'done');
      expect(r.hasActiveFlow, isFalse);
    });

    test(
      'flow returning incompatible route type throws ArgumentError',
      () async {
        // A modal route that's not part of the router's R hierarchy.
        // Constructed inline to bypass sealed enforcement at the test
        // boundary.
        final r = GateRouter<_R>(initial: const _Home());
        expect(
          () => r.run(const _ForeignFlow()),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('sub-router push/pop work within the flow', () async {
      final r = GateRouter<_R>(initial: const _Home());
      final future = r.run(const _StringFlow());
      final flow = r.activeFlows.last.router;

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
      final flow = r.activeFlows.last.router;
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

  group('Nested modal flows', () {
    test('activeFlows empty by default', () {
      final r = GateRouter<_R>(initial: const _Home());
      expect(r.activeFlows, isEmpty);
    });

    test('activeFlows list ordered oldest-first', () async {
      final r = GateRouter<_R>(initial: const _Home());
      final outer = r.run<String>(const _StringFlow());
      final inner = r.run<bool>(const _BoolFlow());

      expect(r.activeFlows.length, 2);
      expect(r.activeFlows[0].route, isA<_StringFlow>());
      expect(r.activeFlows[1].route, isA<_BoolFlow>());

      r.completeFlow<bool>(false);
      await inner;
      r.completeFlow<String>('outer');
      await outer;
    });

    test('each nested flow has an independent router', () async {
      final r = GateRouter<_R>(initial: const _Home());
      final outer = r.run<String>(const _StringFlow());

      final outerFlowRouter = r.activeFlows.last.router;
      // Push something inside the outer flow.
      await outerFlowRouter.push(const _SecondStep('outer-step'));

      final inner = r.run<bool>(const _BoolFlow());
      final innerFlowRouter = r.activeFlows.last.router;

      // The two flow routers are distinct.
      expect(identical(outerFlowRouter, innerFlowRouter), isFalse);

      // Outer flow's stack is unchanged by inner flow's operations.
      expect(outerFlowRouter.stack, [
        const _StringFlow(),
        const _SecondStep('outer-step'),
      ]);
      expect(innerFlowRouter.stack, [const _BoolFlow()]);

      // Push something inside the inner flow.
      await innerFlowRouter.push(const _SecondStep('inner-step'));
      expect(innerFlowRouter.stack, [
        const _BoolFlow(),
        const _SecondStep('inner-step'),
      ]);
      // Outer flow still untouched.
      expect(outerFlowRouter.stack, [
        const _StringFlow(),
        const _SecondStep('outer-step'),
      ]);

      r.completeFlow<bool>(true);
      await inner;
      r.completeFlow<String>('done');
      await outer;
    });

    test('completeFlow always targets the topmost flow', () async {
      final r = GateRouter<_R>(initial: const _Home());
      final outer = r.run<String>(const _StringFlow());
      final inner = r.run<bool>(const _BoolFlow());

      // Completing while the inner is active resolves the inner.
      r.completeFlow<bool>(true);
      expect(await inner, isTrue);
      // Outer still pending.
      expect(r.activeFlows.length, 1);
      expect(r.activeFlows.last.route, isA<_StringFlow>());

      // Subsequent completeFlow resolves the outer.
      r.completeFlow<String>('after-inner');
      expect(await outer, 'after-inner');
      expect(r.hasActiveFlow, isFalse);
    });

    test('dismissFlow only dismisses the topmost', () async {
      final r = GateRouter<_R>(initial: const _Home());
      final outer = r.run<String>(const _StringFlow());
      final inner = r.run<bool>(const _BoolFlow());

      r.dismissFlow();
      expect(await inner, isNull);
      expect(r.activeFlows.length, 1);
      expect(r.activeFlows.last.route, isA<_StringFlow>());

      r.dismissFlow();
      expect(await outer, isNull);
      expect(r.hasActiveFlow, isFalse);
    });

    test(
      'disposing the router resolves every pending flow with null',
      () async {
        final r = GateRouter<_R>(initial: const _Home());
        final outer = r.run<String>(const _StringFlow());
        final inner = r.run<bool>(const _BoolFlow());

        r.dispose();

        expect(await outer, isNull);
        expect(await inner, isNull);
      },
    );

    test('three levels of nesting unwind LIFO', () async {
      final r = GateRouter<_R>(initial: const _Home());
      final a = r.run<String>(const _StringFlow());
      final b = r.run<bool>(const _BoolFlow());
      final c = r.run<String>(const _StringFlow());

      expect(r.activeFlows.length, 3);

      r.completeFlow<String>('c-result');
      expect(await c, 'c-result');
      expect(r.activeFlows.length, 2);

      r.completeFlow<bool>(false);
      expect(await b, isFalse);
      expect(r.activeFlows.length, 1);

      r.completeFlow<String>('a-result');
      expect(await a, 'a-result');
      expect(r.hasActiveFlow, isFalse);
    });
  });
}

// A modal route NOT in the _R sealed hierarchy — used to test the
// runtime type check inside run<T>.
final class _ForeignFlow extends GateRoute implements GateModalRoute<String> {
  const _ForeignFlow();
}
