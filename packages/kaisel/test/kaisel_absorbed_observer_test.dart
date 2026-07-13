import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// Observer-based analytics (observers: () => [MyAnalyticsObserver()]) must see
// navigations that update an absorbed page in place — push/swap/pop within the
// absorbed group emit no Navigator route events, so kaisel reports them to the
// registered observers as didReplace. Resizing across the breakpoint changes a
// page's rendered route without a navigation and must NOT report.

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

class _Recorder extends NavigatorObserver {
  final replaces = <(Object?, Object?)>[]; // (old arguments, new arguments)
  int pushes = 0;

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replaces.add((oldRoute?.settings.arguments, newRoute?.settings.arguments));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
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
  testWidgets('wide: absorbed push and swap report didReplace with values', (
    tester,
  ) async {
    final (config, recorder) = await _pump(tester, const Size(1000, 800));

    await config.router.push(const _Detail('a'));
    await tester.pumpAndSettle();
    expect(recorder.replaces, [(const _List(), const _Detail('a'))]);

    recorder.replaces.clear();
    await config.router.replaceTop(const _Detail('b'));
    await tester.pumpAndSettle();
    expect(recorder.replaces, [(const _Detail('a'), const _Detail('b'))]);
  });

  testWidgets('resize across the breakpoint reports nothing', (tester) async {
    final (config, recorder) = await _pump(tester, const Size(500, 800));
    await config.router.push(const _Detail('a'));
    await tester.pumpAndSettle();
    recorder.replaces.clear();

    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(500, 800);
    await tester.pumpAndSettle();

    expect(recorder.replaces, isEmpty);
  });

  testWidgets('narrow swap gets no synthetic event (no double-logging)', (
    tester,
  ) async {
    final (config, recorder) = await _pump(tester, const Size(500, 800));
    await config.router.push(const _Detail('a'));
    await tester.pumpAndSettle();
    recorder.replaces.clear();
    final pushesBefore = recorder.pushes;

    await config.router.replaceTop(const _Detail('b'));
    await tester.pumpAndSettle();

    // The Navigator's own real event covers narrow widths; kaisel adds nothing.
    expect(recorder.replaces, isEmpty);
    expect(recorder.pushes, greaterThan(pushesBefore));
  });

  testWidgets('wide: system back within the absorbed group reports the pop', (
    tester,
  ) async {
    final (config, recorder) = await _pump(tester, const Size(1000, 800));
    await config.router.push(const _Detail('a'));
    await tester.pumpAndSettle();
    recorder.replaces.clear();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(config.router.stack, [const _List()]);
    expect(recorder.replaces, [(const _Detail('a'), const _List())]);
  });
}
