import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// Observer-based analytics (observers: () => [MyAnalyticsObserver()]) must see
// navigations that update an absorbed page in place — the Navigator emits no
// route events for them, so kaisel reports them kind-matched: absorbed growth
// as didPush, absorbed shrink as didPop, swaps as didReplace. Resizing across
// the breakpoint changes a page's rendered route without a navigation and must
// report nothing. Synthetic routes are never installed on a Navigator, so
// `route.navigator == null` identifies them here.

sealed class _R extends KaiselRoute {
  const _R();
}

final class _List extends _R {
  const _List();
}

final class _Detail extends _R {
  const _Detail(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}

final class _Thread extends _R {
  const _Thread(this.id);

  final int id;

  @override
  List<Object?> get props => [id];
}

typedef _Event = (String kind, Object? args, Object? otherArgs);

class _Recorder extends NavigatorObserver {
  final synthetic = <_Event>[];
  final syntheticRoutes = <Route<dynamic>>[];

  void _record(String kind, Route<dynamic>? primary, Route<dynamic>? other) {
    if (primary == null || primary.navigator != null) return; // real event
    synthetic.add((
      kind,
      primary.settings.arguments,
      other?.settings.arguments,
    ));
    syntheticRoutes.add(primary);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record('push', route, previousRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record('pop', route, previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _record('replace', newRoute, oldRoute);
}

KaiselPageResult _builder(
  BuildContext context,
  _R route,
  KaiselStackContext<_R> ctx,
) {
  final wide = MediaQuery.sizeOf(context).width >= 700;
  return switch (route) {
    _List() => const KaiselStandalonePage(Center(child: Text('LIST'))),
    _Detail(:final id) =>
      (wide && ctx.previous is _List)
          ? KaiselAbsorbingPage(widget: Center(child: Text('PANES $id')))
          : KaiselStandalonePage(Center(child: Text('DETAIL $id'))),
    _Thread(:final id) =>
      (wide && ctx.position >= 2)
          ? KaiselAbsorbingPage(
              absorbing: 2,
              widget: Center(child: Text('THREE $id')),
            )
          : KaiselStandalonePage(Center(child: Text('THREAD $id'))),
  };
}

Future<(KaiselRouterConfig<_R>, _Recorder)> _pump(
  WidgetTester tester,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final recorder = _Recorder();
  final config = KaiselRouterConfig<_R>.adaptive(
    initial: const _List(),
    builder: _builder,
    observers: () => [recorder],
  );
  addTearDown(config.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: config));
  await tester.pumpAndSettle();
  return (config, recorder);
}

void main() {
  testWidgets('wide: absorbed growth is a didPush, a swap is a didReplace', (
    tester,
  ) async {
    final (config, recorder) = await _pump(tester, const Size(1000, 800));

    await config.router.push(const _Detail('a'));
    await tester.pumpAndSettle();
    expect(recorder.synthetic, [('push', const _Detail('a'), const _List())]);

    recorder.synthetic.clear();
    await config.router.replaceTop(const _Detail('b'));
    await tester.pumpAndSettle();
    expect(recorder.synthetic, [
      ('replace', const _Detail('b'), const _Detail('a')),
    ]);
  });

  testWidgets('wide: system back is a didPop pairing the pushed instance', (
    tester,
  ) async {
    final (config, recorder) = await _pump(tester, const Size(1000, 800));
    await config.router.push(const _Detail('a'));
    await tester.pumpAndSettle();
    final pushed = recorder.syntheticRoutes.single;
    recorder.synthetic.clear();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(config.router.stack, [const _List()]);
    expect(recorder.synthetic, [('pop', const _Detail('a'), const _List())]);
    expect(identical(recorder.syntheticRoutes.last, pushed), isTrue);
  });

  testWidgets('resize across the breakpoint reports nothing', (tester) async {
    final (config, recorder) = await _pump(tester, const Size(500, 800));
    await config.router.push(const _Detail('a'));
    await tester.pumpAndSettle();
    recorder.synthetic.clear();

    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(500, 800);
    await tester.pumpAndSettle();

    expect(recorder.synthetic, isEmpty);
  });

  testWidgets('narrow swap gets no synthetic event (no double-logging)', (
    tester,
  ) async {
    final (config, recorder) = await _pump(tester, const Size(500, 800));
    await config.router.push(const _Detail('a'));
    await tester.pumpAndSettle();
    recorder.synthetic.clear();

    await config.router.replaceTop(const _Detail('b'));
    await tester.pumpAndSettle();

    expect(recorder.synthetic, isEmpty);
  });

  testWidgets('bare absorbing: 2 — growth is a push, swap is a replace', (
    tester,
  ) async {
    final (config, recorder) = await _pump(tester, const Size(1000, 800));
    await config.router.push(const _Detail('a'));
    await tester.pumpAndSettle();
    recorder.synthetic.clear();

    await config.router.push(const _Thread(1));
    await tester.pumpAndSettle();
    expect(recorder.synthetic, [
      ('push', const _Thread(1), const _Detail('a')),
    ]);

    recorder.synthetic.clear();
    await config.router.replaceTop(const _Thread(2));
    await tester.pumpAndSettle();
    expect(recorder.synthetic, [
      ('replace', const _Thread(2), const _Thread(1)),
    ]);
  });
}
