import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';
import 'package:kaisel/src/kaisel_adaptive.dart' show buildAdaptivePages;
import 'package:kaisel/src/kaisel_default_page.dart' show kaiselDefaultPage;

// Reproduces the customer report: an adaptive master-detail branch on the web.
// Tapping a list item pushes the detail; the shell/URL/stack all update and the
// entry is "absorbed" (DevTools confirms), but the detail pane never builds —
// only the master (list) shows.
//
// Adaptive master-detail keeps the page key stable across the swap (stableId =
// the master entry's id) so the detail swaps in place without animating. On the
// web the default page is _WebTransitionPage — a PageRouteBuilder that captures
// its child at creation — so a same-key update does NOT rebuild the child, and
// the master-detail scaffold never mounts. On non-web the default is
// MaterialPage, which reads its child from the current page, so it works.

sealed class _R extends KaiselRoute {
  const _R();
}

final class _List extends _R {
  const _List();
}

final class _Detail extends _R {
  const _Detail();
}

class _MasterList extends StatelessWidget {
  const _MasterList();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('LIST')));
}

class _DetailPane extends StatelessWidget {
  const _DetailPane();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('DETAIL')));
}

// Detail-over-list absorbs the master into a side-by-side scaffold; otherwise a
// standalone list. (No width gate — the customer's DevTools already confirmed
// absorption; this isolates the page-rebuild behaviour.)
KaiselPageResult _adaptive(
  BuildContext context,
  _R route,
  KaiselStackContext<_R> stack,
) => switch ((route, stack.previous)) {
  (_Detail(), _List()) => const KaiselAbsorbingPage(
    widget: KaiselMasterDetailScaffold(
      master: _MasterList(),
      detail: _DetailPane(),
    ),
  ),
  _ => const KaiselStandalonePage(_MasterList()),
};

class _Harness extends StatefulWidget {
  const _Harness({required this.router, required this.isWeb});

  final KaiselRouter<_R> router;
  final bool isWeb;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  @override
  void initState() {
    super.initState();
    widget.router.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.router.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Navigator(
    pages: buildAdaptivePages<_R>(
      context: context,
      entries: widget.router.entries,
      builder: _adaptive,
      wrap: (ctx) => kaiselDefaultPage<_R>(
        ctx,
        transition: KaiselWebTransition.fade,
        isWeb: widget.isWeb,
      ),
    ),
    onDidRemovePage: (_) {},
  );
}

void main() {
  testWidgets('web: pushing a detail over the list builds the master-detail '
      'scaffold', (tester) async {
    final router = KaiselRouter<_R>(initial: const _List());
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp(home: _Harness(router: router, isWeb: true)),
    );
    expect(find.text('LIST'), findsOneWidget);
    expect(find.text('DETAIL'), findsNothing);

    await router.pushOrReplaceTop(const _Detail());
    await tester.pumpAndSettle();

    expect(find.text('LIST'), findsOneWidget);
    expect(find.text('DETAIL'), findsOneWidget);
  });

  testWidgets('platform pages: the same swap builds the detail (control)', (
    tester,
  ) async {
    final router = KaiselRouter<_R>(initial: const _List());
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp(home: _Harness(router: router, isWeb: false)),
    );
    expect(find.text('DETAIL'), findsNothing);

    await router.pushOrReplaceTop(const _Detail());
    await tester.pumpAndSettle();

    expect(find.text('DETAIL'), findsOneWidget);
  });
}
