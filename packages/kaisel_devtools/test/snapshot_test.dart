import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel_devtools/src/snapshot.dart';

void main() {
  group('fromJson', () {
    test('NavSnapshot decodes version + roots', () {
      final nav = NavSnapshot.fromJson(<String, Object?>{
        'v': 2,
        'roots': <Object?>[
          <String, Object?>{
            'id': 'r0',
            'main': <String, Object?>{
              'depth': 1,
              'canPop': false,
              'entries': <Object?>[],
            },
          },
        ],
      });
      expect(nav.version, 2);
      expect(nav.roots.single.id, 'r0');
    });

    test('defaults fill in for missing fields', () {
      final nav = NavSnapshot.fromJson(const <String, Object?>{});
      expect(nav.version, 1);
      expect(nav.roots, isEmpty);

      final root = RootSnapshot.fromJson(const <String, Object?>{});
      expect(root.id, 'root');
      expect(root.main.depth, 0);
      expect(root.branches, isEmpty);
      expect(root.guardTrace, isNull);
      expect(root.url, isNull);
    });

    test('absent / non-list fields decode defensively', () {
      final entry = EntrySnapshot.fromJson(const <String, Object?>{
        'props': 'not-a-list',
      });
      expect(entry.id, -1);
      expect(entry.props, isEmpty);
      expect(entry.absorbed, isFalse);

      final stack = StackSnapshot.fromJson(const <String, Object?>{
        'entries': 'not-a-list',
      });
      expect(stack.entries, isEmpty);
    });

    test('entry decodes and stringifies props + carries absorbed', () {
      final e = EntrySnapshot.fromJson(const <String, Object?>{
        'id': 3,
        'type': 'Detail',
        'props': <Object?>['a', 1],
        'label': 'Detail(a)',
        'absorbed': true,
      });
      expect(e.id, 3);
      expect(e.type, 'Detail');
      expect(e.props, <String>['a', '1']);
      expect(e.label, 'Detail(a)');
      expect(e.absorbed, isTrue);
    });

    test('entry label falls back to type, then "?"', () {
      expect(
        EntrySnapshot.fromJson(const <String, Object?>{'type': 'Home'}).label,
        'Home',
      );
      expect(EntrySnapshot.fromJson(const <String, Object?>{}).label, '?');
    });

    test('shell / module / flow / guard decode nested stacks', () {
      final shell = ShellSnapshot.fromJson(const <String, Object?>{
        'type': 'Branched',
        'activeBranch': 1,
        'branchCount': 2,
        'branches': <Object?>[
          <String, Object?>{
            'index': 0,
            'routeType': 'Home',
            'stack': <String, Object?>{
              'depth': 1,
              'entries': <Object?>[
                <String, Object?>{'id': 0, 'label': 'Home'},
              ],
            },
          },
        ],
      });
      expect(shell.activeBranch, 1);
      expect(shell.branches.single.stack.entries.single.label, 'Home');

      final module = ModuleSnapshot.fromJson(const <String, Object?>{
        'prefix': '/c',
        'routeType': 'Checkout',
        'stack': <String, Object?>{'entries': <Object?>[]},
      });
      expect(module.prefix, '/c');
      expect(module.routeType, 'Checkout');

      final flow = FlowSnapshot.fromJson(const <String, Object?>{
        'depth': 1,
        'type': 'AddCard',
        'resultType': 'bool',
        'stack': <String, Object?>{'entries': <Object?>[]},
      });
      expect(flow.resultType, 'bool');

      final guard = GuardTrace.fromJson(const <String, Object?>{
        'input': <Object?>['A'],
        'steps': <Object?>[
          <String, Object?>{
            'guard': '#0',
            'in': <Object?>['A'],
            'out': <Object?>['B'],
            'changed': true,
          },
        ],
        'output': <Object?>['B'],
      });
      expect(guard.input, <String>['A']);
      expect(guard.steps.single.guard, '#0');
      expect(guard.steps.single.input, <String>['A']);
      expect(guard.steps.single.output, <String>['B']);
      expect(guard.steps.single.changed, isTrue);
      expect(guard.output, <String>['B']);
    });
  });

  group('value equality', () {
    EntrySnapshot entry(int id, String label, {bool absorbed = false}) =>
        EntrySnapshot(
          id: id,
          type: 'T',
          props: const <String>['p'],
          label: label,
          absorbed: absorbed,
        );

    test('eqFields compares element-wise and recurses into nested lists', () {
      expect(eqFields(<Object?>['a', 1], <Object?>['a', 1]), isTrue);
      expect(eqFields(<Object?>['a', 1], <Object?>['a', 2]), isFalse);
      expect(eqFields(<Object?>['a'], <Object?>['a', 'b']), isFalse);
      expect(
        eqFields(
          <Object?>[
            <Object?>['x'],
          ],
          <Object?>[
            <Object?>['x'],
          ],
        ),
        isTrue,
      );
      expect(
        eqFields(
          <Object?>[
            <Object?>['x'],
          ],
          <Object?>[
            <Object?>['y'],
          ],
        ),
        isFalse,
      );
    });

    test('entries are equal iff every field matches', () {
      expect(entry(1, 'Home'), entry(1, 'Home'));
      expect(entry(1, 'Home').hashCode, entry(1, 'Home').hashCode);
      expect(entry(1, 'Home'), isNot(entry(2, 'Home')));
      expect(entry(1, 'Home'), isNot(entry(1, 'Detail')));
      expect(entry(1, 'Home'), isNot(entry(1, 'Home', absorbed: true)));
    });

    test('a props difference makes entries unequal', () {
      final a = EntrySnapshot(
        id: 1,
        type: 'T',
        props: const <String>['x'],
        label: 'L',
        absorbed: false,
      );
      final b = EntrySnapshot(
        id: 1,
        type: 'T',
        props: const <String>['y'],
        label: 'L',
        absorbed: false,
      );
      expect(a, isNot(b));
    });

    test('stack equality is deep over its entries', () {
      StackSnapshot stack(List<EntrySnapshot> e) =>
          StackSnapshot(depth: e.length, canPop: e.length > 1, entries: e);
      expect(
        stack(<EntrySnapshot>[entry(1, 'A')]),
        stack(<EntrySnapshot>[entry(1, 'A')]),
      );
      expect(
        stack(<EntrySnapshot>[entry(1, 'A')]),
        isNot(stack(<EntrySnapshot>[entry(1, 'B')])),
      );
    });

    test('shell equality is deep over branches → stack → entries', () {
      ShellSnapshot shell(String topLabel) => ShellSnapshot(
        type: 'S',
        activeBranch: 0,
        branchCount: 1,
        branches: <BranchSnapshot>[
          BranchSnapshot(
            index: 0,
            routeType: 'R',
            stack: StackSnapshot(
              depth: 1,
              canPop: false,
              entries: <EntrySnapshot>[entry(0, topLabel)],
            ),
          ),
        ],
      );
      expect(shell('A'), shell('A'));
      expect(shell('A'), isNot(shell('B')));
    });

    test('guard trace + problem equality', () {
      GuardStep step(bool changed) => GuardStep(
        guard: '#0',
        input: const <String>['A'],
        output: const <String>['B'],
        changed: changed,
      );
      expect(
        GuardTrace(
          input: const <String>['A'],
          steps: <GuardStep>[step(true)],
          output: const <String>['B'],
        ),
        GuardTrace(
          input: const <String>['A'],
          steps: <GuardStep>[step(true)],
          output: const <String>['B'],
        ),
      );
      expect(step(true), isNot(step(false)));

      ProblemSnapshot problem(String detail) =>
          ProblemSnapshot(kind: 'noOp', router: 'main', detail: detail);
      expect(problem('d'), problem('d'));
      expect(problem('d'), isNot(problem('e')));
    });
  });
}
