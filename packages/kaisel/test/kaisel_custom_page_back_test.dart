import 'package:flutter/cupertino.dart' show CupertinoPage;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// kaisel can only count drawers on routes it creates, so with a custom
// pageWrapper the back button relies on the delegate offering back to the
// shell's own navigator first.

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

final class _Deep extends _S {
  const _Deep();
}

Widget _screen(String title) => Scaffold(
  appBar: AppBar(title: Text(title)),
  drawer: const Drawer(child: Text('drawer')),
);

Widget _page(BuildContext context, _S route) => switch (route) {
  _Feed() => _screen('feed'),
  _Deep() => _screen('deep'),
};

Page<Object?> _material(KaiselPageWrapperContext<_S> ctx) =>
    MaterialPage<Object?>(key: ctx.key, child: ctx.child);

Page<Object?> _cupertino(KaiselPageWrapperContext<_S> ctx) =>
    CupertinoPage<Object?>(key: ctx.key, child: ctx.child);

class _Mod extends RouteModule<_S> {
  const _Mod(this.wrapper);

  final KaiselPageWrapper<_S> wrapper;

  @override
  List<_S> get initialStack => const [_Feed()];

  @override
  Widget buildPage(BuildContext context, _S route) => _page(context, route);

  @override
  KaiselPageWrapper<_S> get pageWrapper => wrapper;
}

Future<KaiselRouter<_App>> _pump(
  WidgetTester tester,
  List<_App> stack,
  KaiselPageWrapper<_S> wrapper, {
  List<KaiselGuard<_S>> guards = const [],
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
            branchInitials: const [_Feed()],
            chromeBuilder: (context, i, content, _) => content,
            pageBuilder: _page,
            pageWrapper: wrapper,
            guards: guards,
          ),
          _Tabs() => KaiselBranchedShell.specs(
            branches: [
              KaiselBranchSpec<_S>(
                initial: const _Feed(),
                builder: _page,
                pageWrapper: wrapper,
              ),
            ],
            chromeBuilder: (context, i, content, _) => content,
          ),
          // Modules must be stable instances; a new one rebuilds the router.
          _Module() => KaiselModuleMount<_S>(
            module: identical(wrapper, _material)
                ? const _Mod(_material)
                : const _Mod(_cupertino),
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

Future<bool> _back(WidgetTester tester) async {
  final handled = await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  return handled;
}

Future<void> _pushDeep(WidgetTester tester) async {
  await tester.element(find.text('feed')).push(const _Deep());
  await tester.pumpAndSettle();
}

void main() {
  for (final (wrapperName, wrapper) in [
    ('MaterialPage', _material),
    ('CupertinoPage', _cupertino),
  ]) {
    for (final (hostName, host) in const [
      ('KaiselShell', _Plain()),
      ('KaiselBranchedShell', _Tabs()),
      ('KaiselModuleMount', _Module()),
    ]) {
      group('$hostName with $wrapperName', () {
        testWidgets('back closes a drawer on the first screen', (tester) async {
          final stack = [const _Home(), host];
          final router = await _pump(tester, stack, wrapper);
          await _openDrawer(tester, 'feed');

          expect(await _back(tester), isTrue);
          expect(find.text('drawer'), findsNothing);
          expect(router.stack, stack);

          await _back(tester);
          expect(router.stack, const [_Home()]);
        });

        testWidgets('back closes a drawer on a deeper screen', (tester) async {
          final stack = [const _Home(), host];
          final router = await _pump(tester, stack, wrapper);
          await _pushDeep(tester);
          await _openDrawer(tester, 'deep');

          await _back(tester);
          expect(find.text('drawer'), findsNothing);
          expect(find.text('deep'), findsOneWidget);

          await _back(tester);
          expect(find.text('feed'), findsOneWidget);
          expect(router.stack, stack);
        });

        testWidgets('as the bottom page, back closes the drawer', (
          tester,
        ) async {
          final router = await _pump(tester, [host], wrapper);
          await _openDrawer(tester, 'feed');

          expect(await _back(tester), isTrue);
          expect(find.text('drawer'), findsNothing);
          expect(router.stack, [host]);

          expect(await _back(tester), isFalse);
        });
      });
    }
  }

  testWidgets('without a drawer, a shell guard still decides a deeper pop', (
    tester,
  ) async {
    final stack = [const _Home(), const _Plain()];
    final router = await _pump(
      tester,
      stack,
      _material,
      guards: [
        (current, proposed) =>
            proposed.length < current.length ? current : proposed,
      ],
    );
    await _pushDeep(tester);

    await _back(tester);
    expect(find.text('deep'), findsOneWidget, reason: 'the guard refused');
    expect(router.stack, stack);
  });
}
