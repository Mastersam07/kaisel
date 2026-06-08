import 'dart:convert';
import 'dart:developer' as developer;

import 'package:kaisel_core/framework.dart';
import 'package:test/test.dart';

sealed class _TestRoute extends KaiselRoute {
  const _TestRoute();
}

final class _A extends _TestRoute {
  const _A();
}

final class _B extends _TestRoute {
  const _B();
}

final class _C extends _TestRoute {
  const _C();
}

// Has a field but deliberately no `props` override — the missing-props bug.
final class _Bug extends _TestRoute {
  const _Bug(this.id);
  final String id;
}

class _DecodingRoot extends _FakeRoot {
  _DecodingRoot() : super('decoder');

  @override
  List<String>? debugDecode(String url) =>
      url == '/x' ? const <String>['main: X'] : null;
}

class _FakeRevision extends KaiselChangeNotifier {}

class _FakeRoot implements KaiselInspectable {
  _FakeRoot(this.id);

  final String id;
  final _FakeRevision revision = _FakeRevision();

  @override
  KaiselListenable get debugRevision => revision;

  @override
  List<String>? debugDecode(String url) => null;

  @override
  KaiselRootSnapshot debugSnapshot() => KaiselRootSnapshot(
    id: id,
    main: const KaiselStackSnapshot(
      depth: 1,
      canPop: false,
      entries: <KaiselEntrySnapshot>[
        KaiselEntrySnapshot(
          id: 0,
          type: 'Home',
          props: <String>[],
          label: 'Home',
        ),
      ],
    ),
  );
}

void main() {
  group('snapshot model toJson', () {
    test('entry serialises id/type/props/label', () {
      const entry = KaiselEntrySnapshot(
        id: 7,
        type: 'ChatDetail',
        props: <String>['a'],
        label: 'ChatDetail(a)',
      );
      expect(entry.toJson(), <String, Object?>{
        'id': 7,
        'type': 'ChatDetail',
        'props': <String>['a'],
        'label': 'ChatDetail(a)',
        'absorbed': false,
      });
    });

    test('root omits nothing and nulls absent optionals', () {
      const root = KaiselRootSnapshot(
        id: 'root-0',
        main: KaiselStackSnapshot(
          depth: 0,
          canPop: false,
          entries: <KaiselEntrySnapshot>[],
        ),
      );
      final json = root.toJson();
      expect(json['id'], 'root-0');
      expect(json['branches'], isEmpty);
      expect(json['modules'], isEmpty);
      expect(json['flows'], isEmpty);
      expect(json['guardTrace'], isNull);
      expect(json['url'], isNull);
    });

    test('shell uses kind/branched and nests branch stacks', () {
      const shell = KaiselShellSnapshot(
        type: 'BranchedShellRouter',
        activeBranch: 1,
        branchCount: 2,
        branches: <KaiselBranchSnapshot>[
          KaiselBranchSnapshot(
            index: 0,
            routeType: 'HomeRoute',
            stack: KaiselStackSnapshot(
              depth: 1,
              canPop: false,
              entries: <KaiselEntrySnapshot>[],
            ),
          ),
        ],
      );
      final json = shell.toJson();
      expect(json['kind'], 'branched');
      expect(json['activeBranch'], 1);
      expect((json['branches']! as List<Object?>), hasLength(1));
    });

    test('nav wraps version + roots', () {
      final nav = KaiselNavSnapshot(
        roots: <KaiselRootSnapshot>[_FakeRoot('a').debugSnapshot()],
      );
      final json = nav.toJson();
      expect(json['v'], 1);
      expect((json['roots']! as List<Object?>), hasLength(1));
    });

    const emptyStack = KaiselStackSnapshot(
      depth: 0,
      canPop: false,
      entries: <KaiselEntrySnapshot>[],
    );

    test('module serialises prefix / routeType / stack', () {
      expect(
        const KaiselModuleSnapshot(
          prefix: '/checkout',
          routeType: 'CheckoutRoute',
          stack: emptyStack,
        ).toJson(),
        <String, Object?>{
          'prefix': '/checkout',
          'routeType': 'CheckoutRoute',
          'stack': <String, Object?>{
            'depth': 0,
            'canPop': false,
            'entries': <Object?>[],
          },
        },
      );
    });

    test('flow serialises depth / type / resultType', () {
      final json = const KaiselFlowSnapshot(
        depth: 1,
        type: 'AddCardFlow',
        resultType: 'CardId?',
        stack: emptyStack,
      ).toJson();
      expect(json['depth'], 1);
      expect(json['type'], 'AddCardFlow');
      expect(json['resultType'], 'CardId?');
    });

    test('guard trace serialises input / steps (in,out,changed) / output', () {
      final json = const KaiselGuardTraceSnapshot(
        input: <String>['Login()'],
        steps: <KaiselGuardStepSnapshot>[
          KaiselGuardStepSnapshot(
            guard: '#0',
            input: <String>['Login()'],
            output: <String>['Home()'],
            changed: true,
          ),
        ],
        output: <String>['Home()'],
      ).toJson();
      expect(json['input'], <String>['Login()']);
      expect(json['output'], <String>['Home()']);
      final step = (json['steps']! as List<Object?>).single! as Map;
      expect(step['guard'], '#0');
      expect(step['in'], <String>['Login()']);
      expect(step['out'], <String>['Home()']);
      expect(step['changed'], isTrue);
    });

    test('problem serialises kind / router / detail', () {
      expect(
        const KaiselProblemSnapshot(
          kind: 'noOp',
          router: 'shell0.branch1',
          detail: 'changed nothing',
        ).toJson(),
        <String, Object?>{
          'kind': 'noOp',
          'router': 'shell0.branch1',
          'detail': 'changed nothing',
        },
      );
    });
  });

  group('KaiselInspector registry', () {
    test('register exposes the root; deregister removes it', () {
      final inspector = KaiselInspector.instance;
      final before = inspector.snapshot().roots.length;

      final root = _FakeRoot('root-under-test');
      final token = inspector.register(root);
      expect(
        inspector.snapshot().roots.map((r) => r.id),
        contains('root-under-test'),
      );

      inspector.deregister(token);
      expect(inspector.snapshot().roots.length, before);
      expect(
        inspector.snapshot().roots.map((r) => r.id),
        isNot(contains('root-under-test')),
      );
    });

    test('snapshot().toJson() carries v and a roots list', () {
      final json = KaiselInspector.instance.snapshot().toJson();
      expect(json['v'], 1);
      expect(json['roots'], isA<List<Object?>>());
    });

    test('snapshotJson encodes the registry snapshot', () {
      final json =
          jsonDecode(KaiselInspector.instance.snapshotJson())
              as Map<String, Object?>;
      expect(json['v'], 1);
      expect(json['roots'], isA<List<Object?>>());
    });

    test('decodeJson previews via the first registered root', () {
      final inspector = KaiselInspector.instance;
      final token = inspector.register(_DecodingRoot());

      final hit =
          jsonDecode(inspector.decodeJson('/x')) as Map<String, Object?>;
      expect(hit['ok'], isTrue);
      expect(hit['lines'], const <String>['main: X']);

      final miss =
          jsonDecode(inspector.decodeJson('/nope')) as Map<String, Object?>;
      expect(miss['ok'], isFalse);
      expect(miss['lines'], isEmpty);

      inspector.deregister(token);
    });

    test('the service-extension handlers return responses', () async {
      final inspector = KaiselInspector.instance;
      final token = inspector.register(_DecodingRoot());

      final snap = await inspector.snapshotResponse(
        'ext.kaisel.snapshot',
        const <String, String>{},
      );
      expect(snap, isA<developer.ServiceExtensionResponse>());

      final decoded = await inspector.decodeResponse(
        'ext.kaisel.decode',
        const <String, String>{'url': '/x'},
      );
      expect(decoded, isA<developer.ServiceExtensionResponse>());

      inspector.deregister(token);
    });
  });

  group('KaiselRouter debug fields', () {
    test('debugAbsorbedPositions round-trips through the setter', () {
      final router = KaiselRouter<_TestRoute>(initial: const _A());
      expect(router.debugAbsorbedPositions, isEmpty);
      router.debugSetAbsorbedPositions(const <int>{0, 2});
      expect(router.debugAbsorbedPositions, const <int>{0, 2});
      router.dispose();
    });

    test('a stack entry stringifies with its id and route', () {
      final router = KaiselRouter<_TestRoute>(initial: const _A());
      expect(
        router.entries.first.toString(),
        matches(r'KaiselStackEntry#\d+\('),
      );
      router.dispose();
    });
  });

  group('KaiselRouter.debugLastGuardRun', () {
    test('is null before any guarded navigation', () {
      final router = KaiselRouter<_TestRoute>(initial: const _A());
      expect(router.debugLastGuardRun, isNull);
      router.dispose();
    });

    test(
      'records input, per-guard steps, and output of the pipeline',
      () async {
        final router = KaiselRouter<_TestRoute>(
          initial: const _A(),
          guards: <KaiselGuard<_TestRoute>>[
            (current, proposed) => proposed,
            (current, proposed) => proposed.last is _B
                ? <_TestRoute>[...proposed, const _C()]
                : proposed,
          ],
        );

        await router.push(const _B());

        final run = router.debugLastGuardRun;
        expect(run, isNotNull);
        expect(run!.input, <_TestRoute>[const _A(), const _B()]);
        expect(run.output, <_TestRoute>[const _A(), const _B(), const _C()]);
        expect(run.steps, hasLength(2));
        expect(run.steps[0].label, '#0');
        expect(run.steps[0].changed, isFalse);
        expect(run.steps[1].label, '#1');
        expect(run.steps[1].changed, isTrue);
        expect(run.steps[1].output, <_TestRoute>[
          const _A(),
          const _B(),
          const _C(),
        ]);
        router.dispose();
      },
    );

    test('stays null when no guards are registered', () async {
      final router = KaiselRouter<_TestRoute>(initial: const _A());
      await router.push(const _B());
      expect(router.debugLastGuardRun, isNull);
      router.dispose();
    });
  });

  group('KaiselRouter.debugLastNoOp', () {
    test('records a no-op pushOrReplaceTop, clears on a real change', () async {
      final router = KaiselRouter<_TestRoute>(initial: const _A());

      await router.push(const _Bug('x'));
      expect(
        router.debugLastNoOp,
        isNull,
        reason: 'a real push is not a no-op',
      );

      // _Bug('x') == _Bug('y') (no props), so this replaceTop changes nothing.
      await router.pushOrReplaceTop(const _Bug('y'));
      final noOp = router.debugLastNoOp;
      expect(noOp, isNotNull);
      expect(noOp!.top, '_Bug'); // toString without props — itself a tell
      expect(noOp.depth, 2);

      await router.push(const _A());
      expect(router.debugLastNoOp, isNull, reason: 'a real change clears it');
      router.dispose();
    });

    test('a genuinely-distinct route is not a no-op', () async {
      final router = KaiselRouter<_TestRoute>(initial: const _A());
      await router.push(const _B());
      expect(router.debugLastNoOp, isNull);
      router.dispose();
    });

    test(
      'URL restoration re-applying the current stack is NOT flagged',
      () async {
        final router = KaiselRouter<_TestRoute>(initial: const _A());
        // The platform route-information provider re-applies the initial route
        // on startup; that benign sync must not look like the missing-props bug.
        await router.applyFromInformation(const <_TestRoute>[_A()]);
        expect(router.debugLastNoOp, isNull);
        router.dispose();
      },
    );

    test('restoreStack re-applying the current stack is NOT flagged', () async {
      final router = KaiselRouter<_TestRoute>(initial: const _A());
      await router.restoreStack(const <KaiselRoute>[_A()]);
      expect(router.debugLastNoOp, isNull);
      router.dispose();
    });

    test('set re-applying a value-equal stack is NOT flagged', () async {
      final router = KaiselRouter<_TestRoute>(initial: const _A());
      await router.push(const _Bug('x'));
      // A reactive app re-deriving the stack from state may set an equal one.
      await router.set(const <_TestRoute>[_A(), _Bug('y')]);
      expect(router.debugLastNoOp, isNull);
      router.dispose();
    });

    test('popUntil when already at the target is NOT flagged', () async {
      final router = KaiselRouter<_TestRoute>(initial: const _A());
      await router.push(const _B());
      // "Ensure we're at _B" — already there, so this is an expected no-op.
      await router.popUntil((r) => r is _B);
      expect(router.debugLastNoOp, isNull);
      router.dispose();
    });

    test(
      'a guard redirect that lands on the current stack is NOT flagged',
      () async {
        final router = KaiselRouter<_TestRoute>(
          initial: const _A(),
          guards: <KaiselGuard<_TestRoute>>[
            // Block _B by redirecting back to the current [_A] stack.
            (current, proposed) =>
                proposed.last is _B ? const <_TestRoute>[_A()] : proposed,
          ],
        );
        // The proposal [_A, _B] genuinely differs from current; the guard
        // collapses it to [_A]. That no-op is the guard's doing, not a bug.
        await router.push(const _B());
        expect(router.debugLastNoOp, isNull);
        router.dispose();
      },
    );
  });
}
