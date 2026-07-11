import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// A scaffold-free adaptive layout: a linear stack collapsed into one page at
// wide widths via KaiselAbsorbingPage(absorbing: position). No master-detail or
// supporting-pane scaffold — just the primitive plus a plain widget.

sealed class _Step extends KaiselRoute {
  const _Step();
  String get title;
}

final class _S1 extends _Step {
  const _S1();
  @override
  String get title => 'One';
}

final class _S2 extends _Step {
  const _S2();
  @override
  String get title => 'Two';
}

final class _S3 extends _Step {
  const _S3();
  @override
  String get title => 'Three';
}

KaiselPageResult _builder(
  BuildContext context,
  _Step route,
  KaiselStackContext<_Step> ctx,
) {
  final wide = MediaQuery.sizeOf(context).width >= 820;

  if (!wide) {
    return KaiselStandalonePage(Center(child: Text('SCREEN ${route.title}')));
  }
  if (!ctx.isTop) {
    return const KaiselStandalonePage(SizedBox.shrink());
  }
  final page = Center(child: Text('STEPPER CURRENT ${route.title}'));
  return ctx.position == 0
      ? KaiselStandalonePage(page)
      : KaiselAbsorbingPage(widget: page, absorbing: ctx.position);
}

Future<KaiselRouterConfig<_Step>> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final config = KaiselRouterConfig<_Step>.adaptive(
    initial: const _S1(),
    builder: _builder,
  );
  addTearDown(config.dispose);

  await tester.pumpWidget(MaterialApp.router(routerConfig: config));
  await tester.pumpAndSettle();
  return config;
}

void main() {
  testWidgets('wide: the whole stack collapses into one absorbing page', (
    tester,
  ) async {
    final config = await _pump(tester, const Size(1000, 800));
    await config.router.push(const _S2());
    await config.router.push(const _S3());
    await tester.pumpAndSettle();

    // One collapsed page showing the current step; the entries below are
    // absorbed, not rendered as their own screens.
    expect(find.text('STEPPER CURRENT Three'), findsOneWidget);
    expect(find.text('SCREEN One'), findsNothing);
    expect(find.text('SCREEN Two'), findsNothing);
  });

  testWidgets('narrow: steps stay separate stacked screens', (tester) async {
    final config = await _pump(tester, const Size(500, 800));
    await config.router.push(const _S2());
    await tester.pumpAndSettle();

    expect(find.text('SCREEN Two'), findsOneWidget);
    expect(find.text('SCREEN One'), findsNothing); // offstage under the top
    expect(find.textContaining('STEPPER'), findsNothing);
  });

  testWidgets('wide: popping re-collapses to the new top', (tester) async {
    final config = await _pump(tester, const Size(1000, 800));
    await config.router.push(const _S2());
    await config.router.push(const _S3());
    await tester.pumpAndSettle();

    await config.router.pop();
    await tester.pumpAndSettle();
    expect(find.text('STEPPER CURRENT Two'), findsOneWidget);
    expect(find.text('STEPPER CURRENT Three'), findsNothing);
  });
}
