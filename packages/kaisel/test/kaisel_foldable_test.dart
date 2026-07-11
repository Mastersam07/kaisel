import 'dart:ui' show DisplayFeature, DisplayFeatureType, DisplayFeatureState;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// Foldable-aware adaptive layout: folded/narrow stacks the screens; a vertical
// fold (or a wide flat screen) absorbs them into two panes. The fold is faked via
// MediaQueryData.displayFeatures.

sealed class _R extends KaiselRoute {
  const _R();
}

final class _Inbox extends _R {
  const _Inbox();
}

final class _Message extends _R {
  const _Message(this.id);
  final int id;
  @override
  List<Object?> get props => [id];
}

DisplayFeature? _verticalFold(MediaQueryData mq) {
  for (final f in mq.displayFeatures) {
    final vertical =
        f.bounds.left > 0 && f.bounds.height >= mq.size.height * 0.9;
    final isFold =
        f.type == DisplayFeatureType.fold || f.type == DisplayFeatureType.hinge;
    if (vertical && isFold) return f;
  }
  return null;
}

class _TwoPane extends StatelessWidget {
  const _TwoPane({required this.start, required this.end, this.hinge});
  final Widget start;
  final Widget end;
  final Rect? hinge;

  @override
  Widget build(BuildContext context) {
    final h = hinge;
    if (h == null) {
      return Row(
        children: [
          Expanded(flex: 2, child: start),
          Expanded(flex: 3, child: end),
        ],
      );
    }
    return Row(
      children: [
        SizedBox(width: h.left, child: start),
        SizedBox(width: h.width),
        Expanded(child: end),
      ],
    );
  }
}

KaiselPageResult _builder(
  BuildContext context,
  _R route,
  KaiselStackContext<_R> ctx,
) {
  final mq = MediaQuery.of(context);
  final fold = _verticalFold(mq);
  final spanned = fold != null || mq.size.width >= 700;

  return switch ((ctx.previous, route, spanned)) {
    (_Inbox(), _Message(:final id), true) => KaiselAbsorbingPage(
      widget: _TwoPane(
        start: const Center(child: Text('INBOX')),
        end: Center(child: Text('MSG $id')),
        hinge: fold?.bounds,
      ),
    ),
    (_, _Message(:final id), _) => KaiselStandalonePage(
      Center(child: Text('MSG $id')),
    ),
    _ => const KaiselStandalonePage(Center(child: Text('INBOX'))),
  };
}

Future<KaiselRouterConfig<_R>> _pump(
  WidgetTester tester, {
  required Size size,
  List<DisplayFeature> features = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final config = KaiselRouterConfig<_R>.adaptive(
    initial: const _Inbox(),
    builder: _builder,
  );
  addTearDown(config.dispose);

  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: config,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(displayFeatures: features),
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return config;
}

void main() {
  testWidgets('folded/narrow: message is a full screen, inbox offstage', (
    tester,
  ) async {
    final config = await _pump(tester, size: const Size(480, 900));
    await config.router.push(const _Message(2));
    await tester.pumpAndSettle();

    expect(find.text('MSG 2'), findsOneWidget);
    expect(find.text('INBOX'), findsNothing);
  });

  testWidgets('spanned across a fold: both panes render', (tester) async {
    const fold = DisplayFeature(
      bounds: Rect.fromLTWH(790, 0, 20, 1000),
      type: DisplayFeatureType.fold,
      state: DisplayFeatureState.postureFlat,
    );
    final config = await _pump(
      tester,
      size: const Size(1600, 1000),
      features: [fold],
    );
    await config.router.push(const _Message(2));
    await tester.pumpAndSettle();

    expect(find.text('INBOX'), findsOneWidget);
    expect(find.text('MSG 2'), findsOneWidget);
  });

  testWidgets('wide flat screen (no fold): still two panes', (tester) async {
    final config = await _pump(tester, size: const Size(1200, 800));
    await config.router.push(const _Message(2));
    await tester.pumpAndSettle();

    expect(find.text('INBOX'), findsOneWidget);
    expect(find.text('MSG 2'), findsOneWidget);
  });
}
