import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

sealed class _HomeRoute extends KaiselRoute {
  const _HomeRoute();
}

final class _HomeRoot extends _HomeRoute {
  const _HomeRoot();
}

sealed class _DiscoverRoute extends KaiselRoute {
  const _DiscoverRoute();
}

final class _DiscoverRoot extends _DiscoverRoute {
  const _DiscoverRoot();
}

sealed class _ProfileRoute extends KaiselRoute {
  const _ProfileRoute();
}

final class _ProfileRoot extends _ProfileRoute {
  const _ProfileRoot();
}

List<KaiselBranchSpec> _branches(List<String> built) => [
  KaiselBranchSpec<_HomeRoute>(
    initial: const _HomeRoot(),
    builder: (context, route) {
      built.add('home');
      return const Text('home-screen');
    },
  ),
  KaiselBranchSpec<_DiscoverRoute>(
    initial: const _DiscoverRoot(),
    builder: (context, route) {
      built.add('discover');
      return const Text('discover-screen');
    },
  ),
  KaiselBranchSpec<_ProfileRoute>(
    initial: const _ProfileRoot(),
    builder: (context, route) {
      built.add('profile');
      return const Text('profile-screen');
    },
  ),
];

Widget _chrome(
  BuildContext context,
  int active,
  Widget content,
  void Function(int) switchBranch,
) {
  return Scaffold(
    body: Column(
      children: [
        Expanded(child: content),
        Row(
          children: [
            for (var i = 0; i < 3; i++)
              TextButton(
                key: ValueKey('tab$i'),
                onPressed: () => switchBranch(i),
                child: Text('tab$i'),
              ),
          ],
        ),
      ],
    ),
  );
}

void main() {
  testWidgets('a custom lazyBranchContentBuilder builds branches on demand', (
    tester,
  ) async {
    final built = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: KaiselBranchedShell.specs(
          lazy: true,
          branches: _branches(built),
          lazyBranchContentBuilder:
              (context, active, count, buildBranch, switchBranch) =>
                  buildBranch(context, active),
          chromeBuilder: _chrome,
        ),
      ),
    );

    expect(built.toSet(), {'home'});
    expect(find.text('home-screen'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tab1')));
    await tester.pumpAndSettle();
    expect(built.contains('discover'), isTrue);
    expect(find.text('discover-screen'), findsOneWidget);
    expect(built.contains('profile'), isFalse);
  });

  test('lazyBranchContentBuilder requires lazy: true', () {
    expect(
      () => KaiselBranchedShell.specs(
        lazy: false,
        branches: _branches([]),
        lazyBranchContentBuilder:
            (context, active, count, buildBranch, switchBranch) =>
                buildBranch(context, active),
        chromeBuilder: _chrome,
      ),
      throwsAssertionError,
    );
  });
}
