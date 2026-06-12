import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel_devtools/src/snapshot.dart';
import 'package:kaisel_devtools/src/transitions.dart';

Map<String, Object?> _stackJson(List<String> labels) => <String, Object?>{
  'depth': labels.length,
  'canPop': labels.length > 1,
  'entries': <Object?>[
    for (var i = 0; i < labels.length; i++)
      <String, Object?>{'id': i, 'label': labels[i]},
  ],
};

NavSnapshot _navMain(
  List<String> labels, {
  List<Map<String, Object?>> problems = const <Map<String, Object?>>[],
  List<String> origin = const <String>[],
}) => NavSnapshot.fromJson(<String, Object?>{
  'v': 1,
  'roots': <Object?>[
    <String, Object?>{
      'id': 'r',
      'main': _stackJson(labels),
      'problems': problems,
      'origin': origin,
    },
  ],
});

NavSnapshot _navShell({
  required int active,
  required List<List<String>> branches,
  List<String> origin = const <String>[],
}) => NavSnapshot.fromJson(<String, Object?>{
  'v': 1,
  'roots': <Object?>[
    <String, Object?>{
      'id': 'r',
      'main': _stackJson(<String>['Home']),
      'origin': origin,
      'branches': <Object?>[
        <String, Object?>{
          'type': 'Shell',
          'activeBranch': active,
          'branchCount': branches.length,
          'branches': <Object?>[
            for (var i = 0; i < branches.length; i++)
              <String, Object?>{
                'index': i,
                'routeType': 'R',
                'stack': _stackJson(branches[i]),
              },
          ],
        },
      ],
    },
  ],
});

EntrySnapshot _e(String label, [int id = 0]) => EntrySnapshot(
  id: id,
  type: 'T',
  props: const <String>[],
  label: label,
  absorbed: false,
);

void main() {
  group('stackOp', () {
    test('grow → push, shrink → pop', () {
      expect(
        stackOp(<EntrySnapshot>[_e('A')], <EntrySnapshot>[_e('A'), _e('B')]),
        'push',
      );
      expect(
        stackOp(<EntrySnapshot>[_e('A'), _e('B')], <EntrySnapshot>[_e('A')]),
        'pop',
      );
    });

    test('top differs → replaceTop, an inner entry differs → set', () {
      expect(
        stackOp(
          <EntrySnapshot>[_e('A'), _e('B')],
          <EntrySnapshot>[_e('A'), _e('C')],
        ),
        'replaceTop',
      );
      expect(
        stackOp(
          <EntrySnapshot>[_e('A'), _e('B')],
          <EntrySnapshot>[_e('X'), _e('B')],
        ),
        'set',
      );
    });

    test('identical or empty → null', () {
      expect(
        stackOp(<EntrySnapshot>[_e('A')], <EntrySnapshot>[_e('A')]),
        isNull,
      );
      expect(stackOp(const <EntrySnapshot>[], const <EntrySnapshot>[]), isNull);
    });
  });

  group('diffTransitions', () {
    test('no previous snapshot, or empty roots → nothing', () {
      expect(diffTransitions(null, _navMain(<String>['A'])), isEmpty);
      final emptyRoots = NavSnapshot.fromJson(const <String, Object?>{
        'roots': <Object?>[],
      });
      expect(diffTransitions(emptyRoots, _navMain(<String>['A'])), isEmpty);
      expect(diffTransitions(_navMain(<String>['A']), emptyRoots), isEmpty);
    });

    test('a main push records the new top label on "main"', () {
      final ts = diffTransitions(
        _navMain(<String>['A']),
        _navMain(<String>['A', 'B']),
      );
      expect(ts, hasLength(1));
      expect(ts.single.op, 'push');
      expect(ts.single.router, 'main');
      expect(ts.single.label, 'B');
    });

    test('a main pop records the removed top label', () {
      final ts = diffTransitions(
        _navMain(<String>['A', 'B']),
        _navMain(<String>['A']),
      );
      expect(ts.single.op, 'pop');
      expect(ts.single.label, 'B');
    });

    test('an unchanged main stack records nothing', () {
      expect(
        diffTransitions(_navMain(<String>['A']), _navMain(<String>['A'])),
        isEmpty,
      );
    });

    test('a newly-appeared no-op problem is recorded', () {
      final before = _navMain(<String>['A']);
      final after = _navMain(
        <String>['A'],
        problems: <Map<String, Object?>>[
          <String, Object?>{'kind': 'noOp', 'router': 'main', 'detail': 'x'},
        ],
      );
      final ts = diffTransitions(before, after);
      expect(ts.any((t) => t.op == 'no-op' && t.router == 'main'), isTrue);
    });

    test(
      'a no-op already present in the previous snapshot is not repeated',
      () {
        const problem = <String, Object?>{
          'kind': 'noOp',
          'router': 'main',
          'detail': 'x',
        };
        final before = _navMain(
          <String>['A'],
          problems: const <Map<String, Object?>>[problem],
        );
        final after = _navMain(
          <String>['A'],
          problems: const <Map<String, Object?>>[problem],
        );
        expect(
          diffTransitions(before, after).where((t) => t.op == 'no-op'),
          isEmpty,
        );
      },
    );

    test('a branch switch is recorded against the shell', () {
      final ts = diffTransitions(
        _navShell(
          active: 0,
          branches: <List<String>>[
            <String>['A'],
            <String>['B'],
          ],
        ),
        _navShell(
          active: 1,
          branches: <List<String>>[
            <String>['A'],
            <String>['B'],
          ],
        ),
      );
      expect(
        ts.any(
          (t) =>
              t.op == 'switchBranch' &&
              t.router == 'shell0' &&
              t.label == 'branch 1',
        ),
        isTrue,
      );
    });

    test('a push inside a branch is recorded with the shell.branch router', () {
      final ts = diffTransitions(
        _navShell(
          active: 0,
          branches: <List<String>>[
            <String>['A'],
            <String>['B'],
          ],
        ),
        _navShell(
          active: 0,
          branches: <List<String>>[
            <String>['A', 'A2'],
            <String>['B'],
          ],
        ),
      );
      expect(
        ts.any(
          (t) =>
              t.op == 'push' && t.router == 'shell0.branch0' && t.label == 'A2',
        ),
        isTrue,
      );
    });
  });

  group('transition origin', () {
    test('a main push carries the snapshot origin (who navigated)', () {
      const frames = <String>['#0 onTap (package:myapp/home.dart:12:3)'];
      final ts = diffTransitions(
        _navMain(<String>['Home']),
        _navMain(<String>['Home', 'Detail'], origin: frames),
      );

      expect(ts.single.op, 'push');
      expect(ts.single.origin, frames);
    });

    test('a branch switch carries the snapshot origin', () {
      const frames = <String>['#0 selectTab (package:myapp/nav.dart:8:1)'];
      final ts = diffTransitions(
        _navShell(
          active: 0,
          branches: <List<String>>[
            <String>['A'],
            <String>['B'],
          ],
        ),
        _navShell(
          active: 1,
          branches: <List<String>>[
            <String>['A'],
            <String>['B'],
          ],
          origin: frames,
        ),
      );

      expect(ts.single.op, 'switchBranch');
      expect(ts.single.origin, frames);
    });

    test('each transition in a sequence keeps its own origin', () {
      // Five pushes, each from a distinct call site. Diffing consecutive
      // snapshots yields one transition per step, and each carries the origin
      // of the snapshot that produced it — so the log shows all five, not just
      // the most recent.
      final snaps = <NavSnapshot>[
        _navMain(<String>['S0']),
        for (var i = 1; i <= 5; i++)
          _navMain(
            <String>[for (var j = 0; j <= i; j++) 'S$j'],
            origin: <String>['#0 step$i (package:myapp/x.dart:$i:1)'],
          ),
      ];

      final log = <Transition>[];
      for (var i = 1; i < snaps.length; i++) {
        log.addAll(diffTransitions(snaps[i - 1], snaps[i]));
      }

      expect(log, hasLength(5));
      for (var i = 0; i < 5; i++) {
        expect(log[i].origin.single, contains('step${i + 1}'));
      }
    });
  });
}
