import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

sealed class _HomeRoute extends KaiselRoute {
  const _HomeRoute();
}

final class _HomeRoot extends _HomeRoute {
  const _HomeRoot();
}

sealed class _FeatureRoute extends KaiselRoute {
  const _FeatureRoute();
}

final class _FeatureRoot extends _FeatureRoute {
  const _FeatureRoot();
}

Widget _app({
  required Future<void> Function() load,
  bool lazy = true,
  Widget Function(BuildContext context, Object error, VoidCallback retry)?
  errorBuilder,
}) {
  return MaterialApp(
    home: KaiselBranchedShell.specs(
      lazy: lazy,
      branches: [
        KaiselBranchSpec<_HomeRoute>(
          initial: const _HomeRoot(),
          builder: (context, route) => const Text('home-screen'),
        ),
        KaiselBranchSpec<_FeatureRoute>.deferred(
          initial: const _FeatureRoot(),
          loadLibrary: load,
          placeholder: const Text('loading'),
          errorBuilder: errorBuilder,
          builder: (context, route) => const Text('feature-screen'),
        ),
      ],
      chromeBuilder: (context, active, branchContent, switchBranch) => Scaffold(
        body: Column(
          children: [
            Expanded(child: branchContent),
            Row(
              children: [
                for (var i = 0; i < 2; i++)
                  TextButton(
                    key: ValueKey('tab$i'),
                    onPressed: () => switchBranch(i),
                    child: Text('tab$i'),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a deferred branch does not load until activated', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(_app(load: () async => loads++));

    expect(loads, 0);
    expect(find.text('home-screen'), findsOneWidget);
    expect(find.text('loading', skipOffstage: false), findsNothing);
  });

  testWidgets('activating shows the placeholder, then the loaded content', (
    tester,
  ) async {
    final completer = Completer<void>();
    var loads = 0;
    await tester.pumpWidget(
      _app(
        load: () {
          loads++;
          return completer.future;
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('tab1')));
    await tester.pump();
    expect(loads, 1);
    expect(find.text('loading'), findsOneWidget);
    expect(find.text('feature-screen'), findsNothing);

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.text('feature-screen'), findsOneWidget);
    expect(find.text('loading'), findsNothing);
  });

  testWidgets('the branch loads once and stays loaded across switches', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(_app(load: () async => loads++));

    await tester.tap(find.byKey(const ValueKey('tab1')));
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(find.text('feature-screen'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tab0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab1')));
    await tester.pumpAndSettle();

    expect(loads, 1);
    expect(find.text('feature-screen'), findsOneWidget);
  });

  testWidgets('a deferred spec requires lazy: true', (tester) async {
    await tester.pumpWidget(_app(load: () async {}, lazy: false));
    expect(tester.takeException(), isAssertionError);
  });

  testWidgets('a load failure shows the errorBuilder', (tester) async {
    await tester.pumpWidget(
      _app(
        load: () async => throw Exception('boom'),
        errorBuilder: (context, error, retry) => Text('error: $error'),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('tab1')));
    await tester.pumpAndSettle();

    expect(find.textContaining('error:'), findsOneWidget);
    expect(find.text('feature-screen'), findsNothing);
  });

  testWidgets('a load failure without an errorBuilder keeps the placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(_app(load: () async => throw Exception('boom')));

    await tester.tap(find.byKey(const ValueKey('tab1')));
    await tester.pumpAndSettle();

    expect(find.text('loading'), findsOneWidget);
    expect(find.text('feature-screen'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('errorBuilder can retry a failed load', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      _app(
        load: () async {
          attempts++;
          if (attempts == 1) throw Exception('boom');
        },
        errorBuilder: (context, error, retry) => TextButton(
          key: const ValueKey('retry'),
          onPressed: retry,
          child: const Text('retry'),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('tab1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('retry')), findsOneWidget);
    expect(find.text('feature-screen'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('retry')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('feature-screen'), findsOneWidget);
  });
}
