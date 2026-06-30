import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';
import 'package:kaisel/src/kaisel_default_page.dart';

sealed class _R extends KaiselRoute {
  const _R();
}

final class _Home extends _R {
  const _Home();
}

KaiselPageWrapperContext<_R> _ctx([Widget child = const SizedBox.shrink()]) =>
    KaiselPageWrapperContext<_R>(
      route: const _Home(),
      child: child,
      key: const ValueKey<int>(7),
      position: 0,
      stackLength: 1,
    );

void main() {
  group('kaiselDefaultPage', () {
    test('off the web → MaterialPage for every transition', () {
      for (final t in KaiselWebTransition.values) {
        expect(
          kaiselDefaultPage(_ctx(), transition: t, isWeb: false),
          isA<MaterialPage<Object?>>(),
          reason: '$t off web',
        );
      }
    });

    test('on web: platform → MaterialPage, fade/none → not', () {
      expect(
        kaiselDefaultPage(
          _ctx(),
          transition: KaiselWebTransition.platform,
          isWeb: true,
        ),
        isA<MaterialPage<Object?>>(),
      );
      expect(
        kaiselDefaultPage(
          _ctx(),
          transition: KaiselWebTransition.fade,
          isWeb: true,
        ),
        isNot(isA<MaterialPage<Object?>>()),
      );
      expect(
        kaiselDefaultPage(
          _ctx(),
          transition: KaiselWebTransition.none,
          isWeb: true,
        ),
        isNot(isA<MaterialPage<Object?>>()),
      );
    });

    test('forwards key, name, and arguments', () {
      final page = kaiselDefaultPage(
        _ctx(),
        transition: KaiselWebTransition.fade,
        isWeb: true,
      );
      expect(page.key, const ValueKey<int>(7));
      expect(page.name, '_Home');
      expect(page.arguments, isA<_Home>());
    });

    testWidgets('web durations: none is instant, fade is quick', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      Duration dur(KaiselWebTransition t, {required bool isWeb}) =>
          (kaiselDefaultPage(
                    _ctx(),
                    transition: t,
                    isWeb: isWeb,
                  ).createRoute(ctx)
                  as TransitionRoute)
              .transitionDuration;

      expect(dur(KaiselWebTransition.none, isWeb: true), Duration.zero);
      expect(
        dur(KaiselWebTransition.fade, isWeb: true),
        const Duration(milliseconds: 150),
      );
    });
  });

  group('KaiselWebTransitionScope', () {
    testWidgets('of returns fade when none is installed', (tester) async {
      late KaiselWebTransition seen;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            seen = KaiselWebTransitionScope.of(context);
            return const SizedBox.shrink();
          },
        ),
      );
      expect(seen, KaiselWebTransition.fade);
    });

    testWidgets('of returns the installed transition and reacts to changes', (
      tester,
    ) async {
      late KaiselWebTransition seen;
      var transition = KaiselWebTransition.none;
      late StateSetter setOuter;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return KaiselWebTransitionScope(
              transition: transition,
              child: Builder(
                builder: (context) {
                  seen = KaiselWebTransitionScope.of(context);
                  return const SizedBox.shrink();
                },
              ),
            );
          },
        ),
      );
      expect(seen, KaiselWebTransition.none);

      setOuter(() => transition = KaiselWebTransition.platform);
      await tester.pump();
      expect(seen, KaiselWebTransition.platform);
    });
  });

  group('default web page rendering', () {
    Future<void> push(WidgetTester tester, Page<Object?> page) async {
      final pages = <Page<Object?>>[
        const MaterialPage<Object?>(child: SizedBox.shrink()),
      ];
      late StateSetter setPages;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              setPages = setState;
              return Navigator(pages: List.of(pages), onDidRemovePage: (_) {});
            },
          ),
        ),
      );
      setPages(() => pages.add(page));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();
    }

    testWidgets('fade transition renders the page', (tester) async {
      await push(
        tester,
        kaiselDefaultPage(
          _ctx(const Text('faded', textDirection: TextDirection.ltr)),
          transition: KaiselWebTransition.fade,
          isWeb: true,
        ),
      );
      expect(find.text('faded'), findsOneWidget);
    });

    testWidgets('none transition renders the page', (tester) async {
      await push(
        tester,
        kaiselDefaultPage(
          _ctx(const Text('instant', textDirection: TextDirection.ltr)),
          transition: KaiselWebTransition.none,
          isWeb: true,
        ),
      );
      expect(find.text('instant'), findsOneWidget);
    });
  });

  testWidgets('KaiselRouterConfig threads webTransition into the scope', (
    tester,
  ) async {
    final config = KaiselRouterConfig<_R>(
      initial: const _Home(),
      builder: (_, _) => const SizedBox.shrink(),
      webTransition: KaiselWebTransition.none,
    );
    addTearDown(config.router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: config));
    await tester.pumpAndSettle();

    final scope = tester.widget<KaiselWebTransitionScope>(
      find.byType(KaiselWebTransitionScope),
    );
    expect(scope.transition, KaiselWebTransition.none);
  });
}
