import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

sealed class _HomeRoute extends KaiselRoute {
  const _HomeRoute();
}

final class _HomeRoot extends _HomeRoute {
  const _HomeRoot();
}

final class _HomeDetail extends _HomeRoute {
  const _HomeDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
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

// A three-branch specs shell whose builders append to [built], so a test can
// see which branches were materialised.
Widget _app(List<String> built, {required bool lazy}) {
  return MaterialApp(
    home: KaiselBranchedShell.specs(
      lazy: lazy,
      branches: [
        KaiselBranchSpec<_HomeRoute>(
          initial: const _HomeRoot(),
          builder: (context, route) {
            built.add('home');
            return switch (route) {
              _HomeRoot() => Scaffold(
                body: Column(
                  children: [
                    const Text('home-root'),
                    TextButton(
                      key: const ValueKey('push-detail'),
                      onPressed: () => context.push(const _HomeDetail('x')),
                      child: const Text('push'),
                    ),
                  ],
                ),
              ),
              _HomeDetail(:final id) => Text('home-detail-$id'),
            };
          },
        ),
        KaiselBranchSpec<_DiscoverRoute>(
          initial: const _DiscoverRoot(),
          builder: (context, route) {
            built.add('discover');
            return const Text('discover-root');
          },
        ),
        KaiselBranchSpec<_ProfileRoute>(
          initial: const _ProfileRoot(),
          builder: (context, route) {
            built.add('profile');
            return const Text('profile-root');
          },
        ),
      ],
      chromeBuilder: (context, active, branchContent, switchBranch) {
        return Scaffold(
          body: Column(
            children: [
              Expanded(child: branchContent),
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
      },
    ),
  );
}

void main() {
  testWidgets('lazy specs builds only the initial branch on mount', (
    tester,
  ) async {
    final built = <String>[];
    await tester.pumpWidget(_app(built, lazy: true));

    expect(built.toSet(), {'home'});
    expect(find.text('home-root'), findsOneWidget);
    expect(find.text('discover-root', skipOffstage: false), findsNothing);
    expect(find.text('profile-root', skipOffstage: false), findsNothing);
  });

  testWidgets('eager specs builds every branch on mount', (tester) async {
    final built = <String>[];
    await tester.pumpWidget(_app(built, lazy: false));

    expect(built.toSet(), {'home', 'discover', 'profile'});
  });

  testWidgets('switching builds the target branch on first activation', (
    tester,
  ) async {
    final built = <String>[];
    await tester.pumpWidget(_app(built, lazy: true));
    expect(built.contains('discover'), isFalse);

    await tester.tap(find.byKey(const ValueKey('tab1')));
    await tester.pumpAndSettle();

    expect(built.contains('discover'), isTrue);
    expect(find.text('discover-root'), findsOneWidget);
    expect(built.contains('profile'), isFalse);
  });

  testWidgets('a built branch keeps its state across tab switches', (
    tester,
  ) async {
    final built = <String>[];
    await tester.pumpWidget(_app(built, lazy: true));

    await tester.tap(find.byKey(const ValueKey('push-detail')));
    await tester.pumpAndSettle();
    expect(find.text('home-detail-x'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tab1')));
    await tester.pumpAndSettle();
    expect(find.text('discover-root'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tab0')));
    await tester.pumpAndSettle();
    expect(find.text('home-detail-x'), findsOneWidget);
  });

  testWidgets('lazy: true rejects a custom branchContentBuilder', (
    tester,
  ) async {
    expect(
      () => KaiselBranchedShell.specs(
        lazy: true,
        branches: [
          KaiselBranchSpec<_HomeRoute>(
            initial: const _HomeRoot(),
            builder: (context, route) => const Text('home'),
          ),
        ],
        chromeBuilder: (context, active, branchContent, switchBranch) =>
            branchContent,
        branchContentBuilder: (context, active, branches, switchBranch) =>
            const SizedBox.shrink(),
      ),
      throwsAssertionError,
    );
  });
}
