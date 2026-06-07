import 'package:kaisel_core/framework.dart';
import 'package:test/test.dart';

class _FakeRevision extends KaiselChangeNotifier {}

class _FakeRoot implements KaiselInspectable {
  _FakeRoot(this.id);

  final String id;
  final _FakeRevision revision = _FakeRevision();

  @override
  KaiselListenable get debugRevision => revision;

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
  });
}
