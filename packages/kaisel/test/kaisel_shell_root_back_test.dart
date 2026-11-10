import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, StandardMethodCodec;
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// The first page of a shell (or module) sits alone in its own Navigator, so
// AppBar used to hide the back arrow there even though system back left the
// shell. These cover the arrow appearing, what tapping it pops, and that
// system back still pops exactly once.

sealed class _App extends KaiselRoute {
  const _App();
}

final class _Home extends _App {
  const _Home();
}

final class _Other extends _App {
  const _Other();
}

final class _Group extends _App {
  const _Group();
}

final class _Tabs extends _App {
  const _Tabs();
}

final class _Module extends _App {
  const _Module();
}

sealed class _G extends KaiselRoute {
  const _G();
}

final class _Cart extends _G {
  const _Cart();
}

final class _Pay extends _G {
  const _Pay();
}

sealed class _T extends KaiselRoute {
  const _T();
}

final class _Feed extends _T {
  const _Feed();
}

final class _Post extends _T {
  const _Post();
}

final class _Profile extends _T {
  const _Profile();
}

class _CheckoutModule extends RouteModule<_G> {
  const _CheckoutModule();

  @override
  List<_G> get initialStack => const [_Cart()];

  @override
  Widget buildPage(BuildContext context, _G route) => switch (route) {
    _Cart() => Scaffold(appBar: AppBar(title: const Text('module-cart'))),
    _Pay() => Scaffold(appBar: AppBar(title: const Text('module-pay'))),
  };
}

Widget _cart(BuildContext context) => Scaffold(
  appBar: AppBar(title: const Text('cart')),
  body: Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () => context.push(const _Pay()),
          child: const Text('to-pay'),
        ),
        TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const AlertDialog(content: Text('dialog')),
          ),
          child: const Text('open-dialog'),
        ),
      ],
    ),
  ),
);

KaiselRouterDelegate<_App> _delegate(
  KaiselRouter<_App> router, {
  bool predictive = false,
  bool rootBackArrow = true,
}) => KaiselRouterDelegate<_App>(
  router: router,
  androidPredictiveBack: predictive,
  builder: (context, route) => switch (route) {
    _Home() => const Scaffold(body: Text('home')),
    _Other() => const Scaffold(body: Text('other')),
    _Group() => KaiselShell<_G>(
      rootBackArrow: rootBackArrow,
      branchInitials: const [_Cart()],
      chromeBuilder: (context, i, content, _) => content,
      pageBuilder: (context, r) => switch (r) {
        _Cart() => _cart(context),
        _Pay() => Scaffold(appBar: AppBar(title: const Text('pay'))),
      },
    ),
    _Tabs() => KaiselBranchedShell.specs(
      rootBackArrow: rootBackArrow,
      branches: [
        KaiselBranchSpec<_T>(
          initial: const _Feed(),
          builder: (context, r) => switch (r) {
            _Feed() => Scaffold(
              appBar: AppBar(title: const Text('feed')),
              body: TextButton(
                onPressed: () => context.push(const _Post()),
                child: const Text('to-post'),
              ),
            ),
            _Post() => Scaffold(appBar: AppBar(title: const Text('post'))),
            _Profile() => const SizedBox(),
          },
        ),
        KaiselBranchSpec<_T>(
          initial: const _Profile(),
          builder: (context, r) =>
              Scaffold(appBar: AppBar(title: const Text('profile'))),
        ),
      ],
      chromeBuilder: (context, i, content, switchTo) => content,
    ),
    _Module() => KaiselModuleMount<_G>(
      module: const _CheckoutModule(),
      rootBackArrow: rootBackArrow,
    ),
  },
);

Future<KaiselRouter<_App>> _pump(
  WidgetTester tester,
  List<_App> stack, {
  bool predictive = false,
  bool rootBackArrow = true,
}) async {
  final router = KaiselRouter<_App>(initial: stack.first);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      routerDelegate: _delegate(
        router,
        predictive: predictive,
        rootBackArrow: rootBackArrow,
      ),
    ),
  );
  await router.set(stack);
  await tester.pumpAndSettle();
  return router;
}

Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

// Android's predictive back arrives over the back gesture channel, not
// handlePopRoute, and previews the pop while the finger moves.
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
  group('KaiselShell', () {
    testWidgets('first page shows a back arrow that pops the shell', (
      tester,
    ) async {
      final router = await _pump(tester, const [_Home(), _Other(), _Group()]);
      expect(find.byType(BackButton), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(router.stack, const [_Home(), _Other()]);
      expect(find.text('other'), findsOneWidget);
    });

    testWidgets('no back arrow when the shell is the bottom page', (
      tester,
    ) async {
      await _pump(tester, const [_Group()]);
      expect(find.text('cart'), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('back from an inner page pops it, then the shell', (
      tester,
    ) async {
      final router = await _pump(tester, const [_Home(), _Group()]);
      await tester.tap(find.text('to-pay'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('cart'), findsOneWidget);
      expect(router.stack, const [_Home(), _Group()]);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(router.stack, const [_Home()]);
    });

    testWidgets('system back pops exactly one page', (tester) async {
      final router = await _pump(tester, const [_Home(), _Other(), _Group()]);
      await _systemBack(tester);
      expect(router.stack, const [_Home(), _Other()]);
    });

    testWidgets('system back closes a dialog before leaving the shell', (
      tester,
    ) async {
      final router = await _pump(tester, const [_Home(), _Group()]);
      await tester.tap(find.text('open-dialog'));
      await tester.pumpAndSettle();
      expect(find.text('dialog'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('dialog'), findsNothing);
      expect(router.stack, const [_Home(), _Group()]);

      await _systemBack(tester);
      expect(router.stack, const [_Home()]);
    });
  });

  group('KaiselBranchedShell', () {
    testWidgets('tab root shows a back arrow that pops the shell', (
      tester,
    ) async {
      final router = await _pump(tester, const [_Home(), _Tabs()]);
      expect(find.byType(BackButton), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(router.stack, const [_Home()]);
    });

    testWidgets('no back arrow when the shell is the bottom page', (
      tester,
    ) async {
      await _pump(tester, const [_Tabs()]);
      expect(find.text('feed'), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('system back pops the shell once from a tab root', (
      tester,
    ) async {
      final router = await _pump(tester, const [_Home(), _Other(), _Tabs()]);
      await _systemBack(tester);
      expect(router.stack, const [_Home(), _Other()]);
    });

    testWidgets('system back pops inside the tab before leaving the shell', (
      tester,
    ) async {
      final router = await _pump(tester, const [_Home(), _Tabs()]);
      await tester.tap(find.text('to-post'));
      await tester.pumpAndSettle();
      expect(find.text('post'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('feed'), findsOneWidget);
      expect(router.stack, const [_Home(), _Tabs()]);

      await _systemBack(tester);
      expect(router.stack, const [_Home()]);
    });
  });

  group('KaiselModuleMount', () {
    testWidgets('first page shows a back arrow that pops the module', (
      tester,
    ) async {
      final router = await _pump(tester, const [_Home(), _Module()]);
      expect(find.text('module-cart'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(router.stack, const [_Home()]);
    });
  });

  group('Android predictive back', () {
    for (final predictive in [false, true]) {
      final label = predictive ? 'with' : 'without';

      testWidgets(
        'leaves a KaiselShell from its first screen, $label preview pages',
        (tester) async {
          final router = await _pump(tester, const [
            _Home(),
            _Other(),
            _Group(),
          ], predictive: predictive);
          expect(find.byType(BackButton), findsOneWidget);
          await _predictiveBack(tester);
          expect(router.stack, const [_Home(), _Other()]);
          expect(find.text('other'), findsOneWidget);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.android),
      );

      testWidgets(
        'leaves a branched shell from a tab root, $label preview pages',
        (tester) async {
          final router = await _pump(tester, const [
            _Home(),
            _Other(),
            _Tabs(),
          ], predictive: predictive);
          await tester.tap(find.text('to-post'));
          await tester.pumpAndSettle();

          await _predictiveBack(tester);
          expect(find.text('feed'), findsOneWidget);
          expect(router.stack, const [_Home(), _Other(), _Tabs()]);

          await _predictiveBack(tester);
          expect(router.stack, const [_Home(), _Other()]);
          expect(find.text('other'), findsOneWidget);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.android),
      );
    }
  });

  group('rootBackArrow: false', () {
    for (final (name, host) in const [
      ('KaiselShell', _Group()),
      ('KaiselBranchedShell', _Tabs()),
      ('KaiselModuleMount', _Module()),
    ]) {
      testWidgets('$name keeps its first screen without an arrow', (
        tester,
      ) async {
        final router = await _pump(tester, [
          const _Home(),
          host,
        ], rootBackArrow: false);
        expect(find.byType(BackButton), findsNothing);

        await _systemBack(tester);
        expect(router.stack, const [_Home()]);
      });
    }
  });
}
