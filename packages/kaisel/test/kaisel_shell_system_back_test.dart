import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, StandardMethodCodec;
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// Reproduce the customer's video: a bottom-nav shell (2 tabs). On tab 1 they tap
// an item (push a detail), then press the Android device back button. The detail
// pops back to the tab root — correctly — but animates *twice*. No PopScope in
// their code: the branched shell installs its own for in-branch back handling.

sealed class _App extends KaiselRoute {
  const _App();
}

final class _MainShell extends _App {
  const _MainShell();
}

sealed class _HomeRoute extends KaiselRoute {
  const _HomeRoute();
}

final class _HomeRoot extends _HomeRoute {
  const _HomeRoot();
}

final class _HomeDetail extends _HomeRoute {
  const _HomeDetail();
}

sealed class _OtherRoute extends KaiselRoute {
  const _OtherRoute();
}

final class _OtherRoot extends _OtherRoute {
  const _OtherRoot();
}

class _Counter {
  int pops = 0;
}

class _CountingObserver extends NavigatorObserver {
  _CountingObserver(this.counter);

  final _Counter counter;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      counter.pops++;
}

int _detailBuilds = 0;

KaiselRouterDelegate<_App> _delegate(
  KaiselRouter<_App> router,
  _Counter counter,
) => KaiselRouterDelegate<_App>(
  router: router,
  observers: () => [_CountingObserver(counter)],
  builder: (context, route) => switch (route) {
    _MainShell() => KaiselBranchedShell.specs(
      branches: [
        KaiselBranchSpec<_HomeRoute>(
          initial: const _HomeRoot(),
          builder: (context, r) => switch (r) {
            _HomeRoot() => Scaffold(
              body: Center(
                child: TextButton(
                  key: const ValueKey('push'),
                  onPressed: () => context.push(const _HomeDetail()),
                  child: const Text('home-root'),
                ),
              ),
            ),
            _HomeDetail() => Builder(
              builder: (_) {
                _detailBuilds++;
                return const Scaffold(body: Center(child: Text('home-detail')));
              },
            ),
          },
        ),
        KaiselBranchSpec<_OtherRoute>(
          initial: const _OtherRoot(),
          builder: (context, r) =>
              const Scaffold(body: Center(child: Text('other-root'))),
        ),
      ],
      chromeBuilder: (context, active, branchContent, switchBranch) => Scaffold(
        body: branchContent,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: active,
          onTap: switchBranch,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Other'),
          ],
        ),
      ),
    ),
  },
);

// Drive Android's predictive-back gesture — the path handlePopRoute() does NOT
// exercise. This is what the device back button uses on recent Flutter/Android.
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
}

void main() {
  testWidgets(
    'shell: Android system back on a pushed detail',
    (tester) async {
      final counter = _Counter();
      final router = KaiselRouter<_App>(initial: const _MainShell());
      addTearDown(router.dispose);
      final delegate = _delegate(router, counter);

      await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
      await tester.pumpAndSettle();
      expect(find.text('home-root'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('push')));
      await tester.pumpAndSettle();
      expect(find.text('home-detail'), findsOneWidget);

      _detailBuilds = 0;
      counter.pops = 0;
      await tester.binding.handlePopRoute();
      final frames = await tester.pumpAndSettle();

      debugPrint(
        'SHELL SYSTEM BACK → pops=${counter.pops} '
        'detailBuildsDuringPop=$_detailBuilds settleFrames=$frames',
      );
      expect(find.text('home-root'), findsOneWidget);
      expect(find.text('home-detail'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'shell: Android PREDICTIVE back on a pushed detail',
    (tester) async {
      final counter = _Counter();
      final router = KaiselRouter<_App>(initial: const _MainShell());
      addTearDown(router.dispose);
      final delegate = _delegate(router, counter);

      await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('push')));
      await tester.pumpAndSettle();
      expect(find.text('home-detail'), findsOneWidget);

      _detailBuilds = 0;
      counter.pops = 0;
      await _predictiveBack(tester);
      final frames = await tester.pumpAndSettle();

      debugPrint(
        'SHELL PREDICTIVE BACK → pops=${counter.pops} '
        'detailBuildsDuringPop=$_detailBuilds settleFrames=$frames',
      );
      expect(find.text('home-root'), findsOneWidget);
      expect(find.text('home-detail'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
