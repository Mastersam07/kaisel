import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, StandardMethodCodec;
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// System back lands on the page hosting a shell, not on the shell's own
// navigator, so a drawer open on a shell screen used to be ignored: the shell
// was popped (or the app backgrounded) with the drawer still open.

sealed class _App extends KaiselRoute {
  const _App();
}

final class _Home extends _App {
  const _Home();
}

final class _Plain extends _App {
  const _Plain();
}

final class _Tabs extends _App {
  const _Tabs();
}

final class _Module extends _App {
  const _Module();
}

sealed class _S extends KaiselRoute {
  const _S();
}

final class _Feed extends _S {
  const _Feed();
}

final class _Other extends _S {
  const _Other();
}

final class _Deep extends _S {
  const _Deep();
}

Widget _screen(String title) => Scaffold(
  appBar: AppBar(title: Text(title)),
  drawer: const Drawer(child: Text('drawer')),
);

Widget _page(BuildContext context, _S route) => switch (route) {
  _Feed() => _screen('feed'),
  _Other() => _screen('other'),
  _Deep() => _screen('deep'),
};

class _Mod extends RouteModule<_S> {
  const _Mod();

  @override
  List<_S> get initialStack => const [_Feed()];

  @override
  Widget buildPage(BuildContext context, _S route) => _page(context, route);
}

Future<KaiselRouter<_App>> _pump(
  WidgetTester tester,
  List<_App> stack, {
  bool rootBackArrow = true,
}) async {
  final router = KaiselRouter<_App>(initial: stack.first);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      routerDelegate: KaiselRouterDelegate<_App>(
        router: router,
        builder: (context, route) => switch (route) {
          _Home() => const Scaffold(body: Text('home')),
          _Plain() => KaiselShell<_S>(
            rootBackArrow: rootBackArrow,
            branchInitials: const [_Feed()],
            chromeBuilder: (context, i, content, _) => content,
            pageBuilder: _page,
          ),
          _Tabs() => KaiselBranchedShell.specs(
            rootBackArrow: rootBackArrow,
            branches: [
              const KaiselBranchSpec<_S>(initial: _Feed(), builder: _page),
              const KaiselBranchSpec<_S>(initial: _Other(), builder: _page),
            ],
            chromeBuilder: (context, i, content, _) => content,
          ),
          _Module() => KaiselModuleMount<_S>(
            module: const _Mod(),
            rootBackArrow: rootBackArrow,
          ),
        },
      ),
    ),
  );
  await router.set(stack);
  await tester.pumpAndSettle();
  return router;
}

Future<void> _openDrawer(WidgetTester tester, String title) async {
  final scaffold = find.ancestor(
    of: find.text(title),
    matching: find.byType(Scaffold),
  );
  tester.state<ScaffoldState>(scaffold.first).openDrawer();
  await tester.pumpAndSettle();
  expect(find.text('drawer'), findsOneWidget);
}

Future<bool> _systemBack(WidgetTester tester) async {
  final handled = await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  return handled;
}

Future<void> _predictiveBack(WidgetTester tester) async {
  const codec = StandardMethodCodec();
  Future<void> send(MethodCall call) =>
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/backgesture',
        codec.encodeMethodCall(call),
        (_) {},
      );
  await send(
    const MethodCall('startBackGesture', <String, Object?>{
      'touchOffset': <double>[5.0, 300.0],
      'progress': 0.0,
      'swipeEdge': 0,
    }),
  );
  await tester.pump();
  await send(
    const MethodCall('updateBackGestureProgress', <String, Object?>{
      'touchOffset': <double>[250.0, 300.0],
      'progress': 0.9,
      'swipeEdge': 0,
    }),
  );
  await tester.pump(const Duration(milliseconds: 60));
  await send(const MethodCall('commitBackGesture'));
  await tester.pumpAndSettle();
}

void main() {
  for (final (name, host) in const [
    ('KaiselShell', _Plain()),
    ('KaiselBranchedShell', _Tabs()),
    ('KaiselModuleMount', _Module()),
  ]) {
    group(name, () {
      testWidgets('back closes the drawer, then leaves', (tester) async {
        final router = await _pump(tester, [const _Home(), host]);
        await _openDrawer(tester, 'feed');

        expect(await _systemBack(tester), isTrue);
        expect(find.text('drawer'), findsNothing);
        expect(router.stack, [const _Home(), host]);

        await _systemBack(tester);
        expect(router.stack, const [_Home()]);
      });

      testWidgets('as the bottom page, back closes the drawer', (tester) async {
        final router = await _pump(tester, [host]);
        await _openDrawer(tester, 'feed');

        expect(await _systemBack(tester), isTrue);
        expect(find.text('drawer'), findsNothing);
        expect(router.stack, [host]);

        expect(await _systemBack(tester), isFalse);
      });

      testWidgets('predictive back closes the drawer, then leaves', (
        tester,
      ) async {
        final router = await _pump(tester, [const _Home(), host]);
        await _openDrawer(tester, 'feed');

        await _predictiveBack(tester);
        expect(find.text('drawer'), findsNothing);
        expect(router.stack, [const _Home(), host]);

        await _predictiveBack(tester);
        expect(router.stack, const [_Home()]);
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));

      testWidgets('on a deeper screen, back closes the drawer first', (
        tester,
      ) async {
        final router = await _pump(tester, [const _Home(), host]);
        await tester.element(find.text('feed')).push(const _Deep());
        await tester.pumpAndSettle();
        await _openDrawer(tester, 'deep');

        await _systemBack(tester);
        expect(find.text('drawer'), findsNothing);
        expect(find.text('deep'), findsOneWidget);

        await _systemBack(tester);
        expect(find.text('feed'), findsOneWidget);
        expect(find.text('deep'), findsNothing);
        expect(router.stack, [const _Home(), host]);
      });

      testWidgets(
        'on a deeper screen, predictive back closes the drawer first',
        (tester) async {
          await _pump(tester, [const _Home(), host]);
          await tester.element(find.text('feed')).push(const _Deep());
          await tester.pumpAndSettle();
          await _openDrawer(tester, 'deep');

          await _predictiveBack(tester);
          expect(find.text('drawer'), findsNothing);
          expect(find.text('deep'), findsOneWidget);

          await _predictiveBack(tester);
          expect(find.text('feed'), findsOneWidget);
          expect(find.text('deep'), findsNothing);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.android),
      );

      testWidgets('rootBackArrow: false still closes the drawer', (
        tester,
      ) async {
        final router = await _pump(tester, [
          const _Home(),
          host,
        ], rootBackArrow: false);
        await _openDrawer(tester, 'feed');

        await _systemBack(tester);
        expect(find.text('drawer'), findsNothing);
        expect(router.stack, [const _Home(), host]);
      });
    });
  }

  testWidgets('a drawer left open on a hidden tab does not block back', (
    tester,
  ) async {
    final router = await _pump(tester, const [_Home(), _Tabs()]);
    await _openDrawer(tester, 'feed');
    tester.element(find.text('feed')).shell().switchTo(1);
    await tester.pumpAndSettle();
    expect(find.text('other'), findsOneWidget);

    await _systemBack(tester);
    expect(router.stack, const [_Home()]);
  });
}
