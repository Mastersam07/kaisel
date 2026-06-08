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
}) => NavSnapshot.fromJson(<String, Object?>{
  'v': 1,
  'roots': <Object?>[
    <String, Object?>{
      'id': 'r',
      'main': _stackJson(labels),
      'problems': problems,
    },
  ],
});

NavSnapshot _navShell({
  required int active,
  required List<List<String>> branches,
}) => NavSnapshot.fromJson(<String, Object?>{
  'v': 1,
  'roots': <Object?>[
    <String, Object?>{
      'id': 'r',
      'main': _stackJson(<String>['Home']),
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
}
