import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

sealed class _Tab extends KaiselRoute {
  const _Tab();
}

final class _TabA extends _Tab {
  const _TabA();
}

final class _TabB extends _Tab {
  const _TabB();
}

sealed class _ARoute extends KaiselRoute {
  const _ARoute();
}

final class _ARoot extends _ARoute {
  const _ARoot();
}

sealed class _BRoute extends KaiselRoute {
  const _BRoute();
}

final class _BRoot extends _BRoute {
  const _BRoot();
}

class _Ticks {
  int count = 0;
}

class _Looping extends StatefulWidget {
  const _Looping(this.ticks);
  final _Ticks ticks;

  @override
  State<_Looping> createState() => _LoopingState();
}

class _LoopingState extends State<_Looping>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..addListener(() => widget.ticks.count++)
          ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

Widget _chrome(
  BuildContext context,
  int active,
  Widget content,
  void Function(int) switchBranch,
) => Column(
  children: [
    Expanded(child: content),
    for (var i = 0; i < 2; i++)
      TextButton(onPressed: () => switchBranch(i), child: Text('tab$i')),
  ],
);

Future<void> _expectHiddenBranchMuted(WidgetTester tester, _Ticks ticks) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  expect(ticks.count, greaterThan(0), reason: 'animates while visible');

  await tester.tap(find.text('tab1'));
  await tester.pump();
  final hiddenAt = ticks.count;
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  expect(ticks.count, hiddenAt, reason: 'muted while its tab is hidden');

  await tester.tap(find.text('tab0'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  expect(ticks.count, greaterThan(hiddenAt), reason: 'resumes when shown');
}

void main() {
  testWidgets('KaiselShell mutes tickers in hidden branches', (tester) async {
    final ticks = _Ticks();
    await tester.pumpWidget(
      MaterialApp(
        home: KaiselShell<_Tab>(
          branchInitials: const [_TabA(), _TabB()],
          pageBuilder: (context, route) => switch (route) {
            _TabA() => _Looping(ticks),
            _TabB() => const SizedBox(),
          },
          chromeBuilder: _chrome,
        ),
      ),
    );

    await _expectHiddenBranchMuted(tester, ticks);
  });

  for (final lazy in [false, true]) {
    testWidgets(
      'KaiselBranchedShell (lazy: $lazy) mutes tickers in hidden branches',
      (tester) async {
        final ticks = _Ticks();
        await tester.pumpWidget(
          MaterialApp(
            home: KaiselBranchedShell.specs(
              lazy: lazy,
              branches: [
                KaiselBranchSpec<_ARoute>(
                  initial: const _ARoot(),
                  builder: (context, route) => _Looping(ticks),
                ),
                KaiselBranchSpec<_BRoute>(
                  initial: const _BRoot(),
                  builder: (context, route) => const SizedBox(),
                ),
              ],
              chromeBuilder: _chrome,
            ),
          ),
        );

        await _expectHiddenBranchMuted(tester, ticks);
      },
    );
  }
}
