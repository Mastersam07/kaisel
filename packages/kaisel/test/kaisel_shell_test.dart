import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// Homogeneous shell: all branches share one route type.
sealed class _Tab extends KaiselRoute {
  const _Tab();
}

final class _TabA extends _Tab {
  const _TabA();
}

final class _TabB extends _Tab {
  const _TabB();
}

void main() {
  group('KaiselShell', () {
    testWidgets('.adaptive builds branches with an adaptive page builder', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: KaiselShell<_Tab>.adaptive(
            branchInitials: const [_TabA(), _TabB()],
            pageBuilder: (context, route, stack) => KaiselStandalonePage(
              Text(
                route is _TabA ? 'tab-a' : 'tab-b',
                textDirection: TextDirection.ltr,
              ),
            ),
            chromeBuilder: (context, active, content, switchBranch) => content,
          ),
        ),
      );

      // Branch 0 (_TabA) is active and rendered through the adaptive builder.
      expect(find.text('tab-a'), findsOneWidget);
    });

    testWidgets('switchTo rebuilds the chrome with the new active branch', (
      tester,
    ) async {
      late void Function(int) switchBranch;
      await tester.pumpWidget(
        MaterialApp(
          home: KaiselShell<_Tab>(
            branchInitials: const [_TabA(), _TabB()],
            pageBuilder: (context, route) => const Scaffold(),
            chromeBuilder: (context, active, content, sb) {
              switchBranch = sb;
              return Column(
                children: [
                  Text('active=$active', textDirection: TextDirection.ltr),
                  Expanded(child: content),
                ],
              );
            },
          ),
        ),
      );

      expect(find.text('active=0'), findsOneWidget);

      // Drives ShellRouter.switchTo → notifyListeners → the shell's internal
      // listener calls setState and the chrome rebuilds.
      switchBranch(1);
      await tester.pump();
      expect(find.text('active=1'), findsOneWidget);
    });

    testWidgets('back pops within the active branch when it has history', (
      tester,
    ) async {
      late BuildContext branchCtx;
      await tester.pumpWidget(
        MaterialApp(
          home: KaiselShell<_Tab>(
            branchInitials: const [_TabA(), _TabB()],
            pageBuilder: (context, route) => switch (route) {
              _TabA() => Builder(
                builder: (c) {
                  branchCtx = c;
                  return const Text(
                    'a-screen',
                    textDirection: TextDirection.ltr,
                  );
                },
              ),
              _TabB() => const Text(
                'b-screen',
                textDirection: TextDirection.ltr,
              ),
            },
            chromeBuilder: (context, active, content, sb) => content,
          ),
        ),
      );

      expect(find.text('a-screen'), findsOneWidget);

      // Push within the active branch (branch 0), giving it back-history.
      await branchCtx.push(const _TabB());
      await tester.pumpAndSettle();
      expect(find.text('b-screen'), findsWidgets);

      // The shell's PopScope intercepts the back and pops within the branch.
      final popScope = tester.widget<PopScope<Object?>>(
        find.byWidgetPredicate((w) => w is PopScope),
      );
      expect(popScope.canPop, isFalse, reason: 'branch has history');
      final onPop = popScope.onPopInvokedWithResult;
      expect(onPop, isNotNull);
      onPop?.call(false, null);
      await tester.pumpAndSettle();
      expect(
        find.text('a-screen'),
        findsOneWidget,
        reason: 'back returned to root',
      );
    });

    testWidgets('branchScope wraps each branch once', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: KaiselShell<_Tab>(
            branchInitials: const [_TabA(), _TabB()],
            pageBuilder: (context, route) => const Scaffold(),
            branchScope: (context, index, child) =>
                KeyedSubtree(key: Key('scope-$index'), child: child),
            chromeBuilder: (context, active, content, sb) => content,
          ),
        ),
      );

      // Branch 1 is offstage inside the IndexedStack, so opt into matching it.
      expect(
        find.byKey(const Key('scope-0'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('scope-1'), skipOffstage: false),
        findsOneWidget,
      );
    });
  });
}
