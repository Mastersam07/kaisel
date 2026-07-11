import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// KaiselSupportingPaneScaffold and multi-entry absorption (absorbing: 2) render
// on the same primitive as master-detail. At wide widths the top route absorbs
// the entries below into one page; at narrow it stays a standalone screen.

sealed class _R extends KaiselRoute {
  const _R();
}

final class _Doc extends _R {
  const _Doc();
}

final class _Comments extends _R {
  const _Comments();
}

final class _Thread extends _R {
  const _Thread(this.id);

  final int id;

  @override
  List<Object?> get props => [id];
}

class _PaneCodec extends KaiselStackCodec<_R> {
  const _PaneCodec();

  @override
  Uri encode(List<_R> stack) => switch (stack.last) {
    _Doc() => Uri(path: '/doc'),
    _Comments() => Uri(path: '/doc/comments'),
    _Thread(:final id) => Uri(path: '/doc/comments/thread/$id'),
  };

  @override
  List<_R>? decode(Uri uri) => switch (uri.pathSegments) {
    [] || ['doc'] => const [_Doc()],
    ['doc', 'comments'] => const [_Doc(), _Comments()],
    ['doc', 'comments', 'thread', final raw] when int.tryParse(raw) != null => [
      const _Doc(),
      const _Comments(),
      _Thread(int.parse(raw)),
    ],
    _ => null,
  };
}

KaiselPageResult _builder(
  BuildContext context,
  _R route,
  KaiselStackContext<_R> ctx,
) {
  final width = MediaQuery.sizeOf(context).width;
  final wide = width >= 900;
  final extraWide = width >= 1300;

  return switch (route) {
    _Doc() => const KaiselStandalonePage(Center(child: Text('DOC'))),

    _Comments() =>
      (ctx.isTop && wide && ctx.previous is _Doc)
          ? const KaiselAbsorbingPage(
              widget: KaiselSupportingPaneScaffold(
                primary: Center(child: Text('DOC')),
                supporting: Center(child: Text('COMMENTS')),
              ),
            )
          : const KaiselStandalonePage(Center(child: Text('COMMENTS'))),

    _Thread(:final id) =>
      (extraWide && ctx.position >= 2)
          ? KaiselAbsorbingPage(
              absorbing: 2,
              widget: Row(
                children: [
                  const Expanded(child: Center(child: Text('DOC'))),
                  const Expanded(child: Center(child: Text('COMMENTS'))),
                  Expanded(child: Center(child: Text('THREAD $id'))),
                ],
              ),
            )
          : KaiselStandalonePage(Center(child: Text('THREAD $id'))),
  };
}

Future<KaiselRouterConfig<_R>> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final config = KaiselRouterConfig<_R>.adaptive(
    initial: const _Doc(),
    builder: _builder,
  );
  addTearDown(config.dispose);

  await tester.pumpWidget(MaterialApp.router(routerConfig: config));
  await tester.pumpAndSettle();
  return config;
}

void main() {
  testWidgets('wide: supporting pane renders both panes at once', (
    tester,
  ) async {
    final config = await _pump(tester, const Size(1000, 800));
    await config.router.push(const _Comments());
    await tester.pumpAndSettle();

    expect(find.text('DOC'), findsOneWidget);
    expect(find.text('COMMENTS'), findsOneWidget);
  });

  testWidgets('narrow: comments is standalone, document offstage', (
    tester,
  ) async {
    final config = await _pump(tester, const Size(500, 800));
    await config.router.push(const _Comments());
    await tester.pumpAndSettle();

    expect(find.text('COMMENTS'), findsOneWidget);
    expect(find.text('DOC'), findsNothing);
  });

  testWidgets('extra-wide: three-pane absorbs the two entries below', (
    tester,
  ) async {
    final config = await _pump(tester, const Size(1400, 900));
    await config.router.push(const _Comments());
    await config.router.push(const _Thread(7));
    await tester.pumpAndSettle();

    expect(find.text('DOC'), findsOneWidget);
    expect(find.text('COMMENTS'), findsOneWidget);
    expect(find.text('THREAD 7'), findsOneWidget);
  });

  group('pane URL codec', () {
    const codec = _PaneCodec();

    test('encodes each stack shape to a path', () {
      expect(codec.encode(const [_Doc()]).path, '/doc');
      expect(codec.encode(const [_Doc(), _Comments()]).path, '/doc/comments');
      expect(
        codec.encode(const [_Doc(), _Comments(), _Thread(2)]).path,
        '/doc/comments/thread/2',
      );
    });

    test('decodes a deep link back to the full stack', () {
      final stack = codec.decode(Uri.parse('/doc/comments/thread/2'));
      expect(stack?.length, 3);
      expect(stack?.last, isA<_Thread>().having((t) => t.id, 'id', 2));
    });

    test('unknown or malformed paths fall back to null', () {
      expect(codec.decode(Uri.parse('/nope')), isNull);
      expect(codec.decode(Uri.parse('/doc/comments/thread/x')), isNull);
    });
  });
}
