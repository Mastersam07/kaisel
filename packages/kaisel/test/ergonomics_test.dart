import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// Two distinct sealed route families, so the accepts-walk has something to
// discriminate on.
sealed class _R extends KaiselRoute {
  const _R();
}

final class _A extends _R {
  const _A();
}

final class _B extends _R {
  const _B();
}

sealed class _BranchR extends KaiselRoute {
  const _BranchR();
}

final class _X extends _BranchR {
  const _X();
}

final class _Y extends _BranchR {
  const _Y();
}

// A modal flow in the _R family, for context.run.
final class _Flow extends _R implements KaiselModalRoute<bool> {
  const _Flow();
}

// Minimal stack codec for the URL test: /a, /b round-trip.
class _StackCodec extends KaiselStackCodec<_R> {
  const _StackCodec();

  @override
  Uri encode(List<_R> stack) =>
      Uri(pathSegments: [for (final r in stack) _seg(r)]);

  @override
  List<_R>? decode(Uri uri) {
    final out = <_R>[];
    for (final segment in uri.pathSegments) {
      final route = _route(segment);
      if (route == null) return null;
      out.add(route);
    }
    return out.isEmpty ? null : out;
  }

  static String _seg(_R route) => switch (route) {
    _A() => 'a',
    _B() => 'b',
    _ => '_',
  };

  static _R? _route(String segment) => switch (segment) {
    'a' => const _A(),
    'b' => const _B(),
    _ => null,
  };
}

void main() {
  group('context.* navigation verbs', () {
    testWidgets('push / pop resolve the nearest router', (tester) async {
      final router = KaiselRouter<_R>(initial: const _A());
      addTearDown(router.dispose);

      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: RouterScope<_R>(
            router: router,
            child: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await ctx.push(const _B());
      expect(router.stack, const [_A(), _B()]);

      await ctx.pushOrReplaceTop(const _B());
      expect(router.stack, const [
        _A(),
        _B(),
      ], reason: 'same type replaces top');

      await ctx.pop();
      expect(router.stack, const [_A()]);

      await ctx.replaceTop(const _B());
      expect(router.stack, const [_B()], reason: 'replaceTop swaps the top');

      await ctx.set(const [_A(), _B()]);
      expect(router.stack, const [
        _A(),
        _B(),
      ], reason: 'set replaces the stack');
    });

    testWidgets('pop throws when no router is in scope', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );

      Object? caught;
      try {
        await ctx.pop();
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<FlutterError>());
      expect('$caught', contains('context.pop()'));
    });

    testWidgets('shell() throws when no shell is in scope', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(ctx.shell, throwsA(isA<FlutterError>()));
    });

    testWidgets('push routes by family — nearest accepting router wins', (
      tester,
    ) async {
      final main = KaiselRouter<_R>(initial: const _A());
      final branch = KaiselRouter<_BranchR>(initial: const _X());
      addTearDown(main.dispose);
      addTearDown(branch.dispose);

      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: RouterScope<_R>(
            router: main,
            child: RouterScope<_BranchR>(
              router: branch,
              child: Builder(
                builder: (c) {
                  ctx = c;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );

      // _Y is a _BranchR → nearest (branch) accepts it.
      await ctx.push(const _Y());
      expect(branch.stack, const [_X(), _Y()]);
      expect(main.stack, const [_A()]);

      // _B is an _R, not a _BranchR → branch rejects, walk up to main.
      await ctx.push(const _B());
      expect(main.stack, const [_A(), _B()]);
      expect(branch.stack, const [_X(), _Y()], reason: 'branch untouched');
    });

    testWidgets('throws a helpful error when no router accepts the route', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );

      Object? caught;
      try {
        await ctx.push(const _A());
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<FlutterError>());
      expect('$caught', contains('No KaiselRouter above this context accepts'));
    });
  });

  group('context.shell()', () {
    testWidgets('switches branches for a branched shell', (tester) async {
      final b1 = KaiselRouter<_BranchR>(initial: const _X());
      final b2 = KaiselRouter<_R>(initial: const _A());
      final shell = BranchedShellRouter(branches: [b1, b2]);
      addTearDown(shell.dispose);
      addTearDown(b1.dispose);
      addTearDown(b2.dispose);

      late BuildContext chromeCtx;
      await tester.pumpWidget(
        MaterialApp(
          home: KaiselBranchedShell(
            shell: shell,
            branches: [
              KaiselBranch<_BranchR>(
                router: b1,
                pageBuilder: (c, r) => const Scaffold(),
              ),
              KaiselBranch<_R>(
                router: b2,
                pageBuilder: (c, r) => const Scaffold(),
              ),
            ],
            chromeBuilder: (context, active, content, switchBranch) {
              chromeCtx = context;
              return content;
            },
          ),
        ),
      );

      expect(shell.activeBranch, 0);
      chromeCtx.shell().switchTo(1);
      await tester.pump();
      expect(shell.activeBranch, 1);
    });
  });

  group('KaiselBranchedShell.specs', () {
    testWidgets('wires the routers and preserves branch state across tab '
        'switches', (tester) async {
      late BuildContext branch0;
      late void Function(int) switchTo;

      await tester.pumpWidget(
        MaterialApp(
          home: KaiselBranchedShell.specs(
            branches: [
              KaiselBranchSpec<_BranchR>(
                initial: const _X(),
                builder: (context, route) => switch (route) {
                  _X() => Builder(
                    builder: (c) {
                      branch0 = c;
                      return const Text(
                        'b0-X',
                        textDirection: TextDirection.ltr,
                      );
                    },
                  ),
                  _Y() => const Text('b0-Y', textDirection: TextDirection.ltr),
                },
              ),
              KaiselBranchSpec<_R>(
                initial: const _A(),
                builder: (context, route) => switch (route) {
                  _A() => const Text('b1-A', textDirection: TextDirection.ltr),
                  _B() => const Text('b1-B', textDirection: TextDirection.ltr),
                  _Flow() => const SizedBox(),
                },
              ),
            ],
            chromeBuilder: (context, active, content, sb) {
              switchTo = sb;
              return content;
            },
          ),
        ),
      );

      expect(find.text('b0-X'), findsOneWidget);

      await branch0.push(const _Y());
      await tester.pumpAndSettle();
      expect(find.text('b0-Y'), findsOneWidget);

      // The branch's stack must survive a switch away and back: the routers
      // are created once, not rebuilt per switch.
      switchTo(1);
      await tester.pumpAndSettle();
      expect(find.text('b1-A'), findsOneWidget);

      switchTo(0);
      await tester.pumpAndSettle();
      expect(
        find.text('b0-Y'),
        findsOneWidget,
        reason: 'branch 0 kept its pushed route',
      );

      // Tearing the shell down disposes the routers it owns (no errors).
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('branchContentBuilder overrides the default IndexedStack', (
      tester,
    ) async {
      var receivedActive = -1;
      var receivedCount = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: KaiselBranchedShell.specs(
            branches: [
              KaiselBranchSpec<_BranchR>(
                initial: const _X(),
                builder: (context, route) => const Scaffold(),
              ),
              KaiselBranchSpec<_R>(
                initial: const _A(),
                builder: (context, route) => const Scaffold(),
              ),
            ],
            branchContentBuilder: (context, active, branches, switchBranch) {
              receivedActive = active;
              receivedCount = branches.length;
              return PageView(children: branches);
            },
            chromeBuilder: (context, active, content, sb) => content,
          ),
        ),
      );

      expect(receivedActive, 0);
      expect(receivedCount, 2);
      expect(find.byType(PageView), findsOneWidget);
      expect(find.byType(IndexedStack), findsNothing);
    });
  });

  group('KaiselRouterConfig', () {
    testWidgets('drives a MaterialApp.router with no manual plumbing', (
      tester,
    ) async {
      final config = KaiselRouterConfig<_R>(
        initial: const _A(),
        builder: (context, route) => switch (route) {
          _A() => const Text('A', textDirection: TextDirection.ltr),
          _B() => const Text('B', textDirection: TextDirection.ltr),
          _Flow() => const SizedBox(),
        },
      );
      addTearDown(config.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: config));
      expect(find.text('A'), findsOneWidget);

      await config.router.push(const _B());
      await tester.pumpAndSettle();
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('wires the codec so a deep link decodes to the stack', (
      tester,
    ) async {
      tester.platformDispatcher.defaultRouteNameTestValue = '/b';
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);

      final config = KaiselRouterConfig<_R>(
        initial: const _A(),
        codec: const StackToConfigCodec<_R>(_StackCodec()),
        builder: (context, route) => switch (route) {
          _A() => const Text('A', textDirection: TextDirection.ltr),
          _B() => const Text('B', textDirection: TextDirection.ltr),
          _Flow() => const SizedBox(),
        },
      );
      addTearDown(config.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: config));
      await tester.pumpAndSettle();

      expect(config.routeInformationProvider, isNotNull);
      expect(config.router.stack, const [_B()]);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('.adaptive drives an adaptive main delegate — absorbs '
        'master-detail at wide widths', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final config = KaiselRouterConfig<_R>.adaptive(
        initial: const _A(),
        builder: (context, route, stack) {
          final wide = MediaQuery.sizeOf(context).width >= 600;
          return switch ((route, stack.previous, wide)) {
            // Detail (_B) over master (_A) at wide width → one absorbed page.
            (_B(), _A(), true) => const KaiselAbsorbingPage(
              widget: Row(
                textDirection: TextDirection.ltr,
                children: [Text('master-A'), Text('detail-B')],
              ),
            ),
            _ => KaiselStandalonePage(
              Text(switch (route) {
                _A() => 'A',
                _B() => 'B',
                _Flow() => 'flow',
              }, textDirection: TextDirection.ltr),
            ),
          };
        },
      );
      addTearDown(config.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: config));
      expect(find.text('A'), findsOneWidget);

      await config.router.push(const _B());
      await tester.pumpAndSettle();

      expect(find.text('master-A'), findsOneWidget);
      expect(find.text('detail-B'), findsOneWidget);
      expect(find.text('A'), findsNothing);
    });
  });

  group('context.run', () {
    testWidgets('opens a flow on the nearest accepting router and returns its '
        'typed result', (tester) async {
      final main = KaiselRouter<_R>(initial: const _A());
      final branch = KaiselRouter<_BranchR>(initial: const _X());
      addTearDown(main.dispose);
      addTearDown(branch.dispose);

      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: RouterScope<_R>(
            router: main,
            child: RouterScope<_BranchR>(
              router: branch,
              child: Builder(
                builder: (c) {
                  ctx = c;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );

      // _Flow is an _R, not a _BranchR — the walk skips the branch and runs it
      // on the main router.
      final result = ctx.run<bool>(const _Flow());
      expect(branch.activeFlows, isEmpty);
      expect(main.activeFlows, isNotEmpty);

      main.completeFlow<bool>(true);
      expect(await result, isTrue);
    });
  });

  group('context.completeFlow / dismissFlow', () {
    KaiselRouterConfig<_R> flowConfig() => KaiselRouterConfig<_R>(
      initial: const _A(),
      builder: (context, route) => switch (route) {
        _A() => const Text('home', textDirection: TextDirection.ltr),
        _B() => const Text('B', textDirection: TextDirection.ltr),
        _Flow() => Builder(
          builder: (c) => Column(
            children: [
              TextButton(
                onPressed: () => c.completeFlow<bool>(true),
                child: const Text('confirm'),
              ),
              TextButton(onPressed: c.dismissFlow, child: const Text('cancel')),
            ],
          ),
        ),
      },
      modalBuilder: (context, flowRoute, flowChild) =>
          Material(child: flowChild),
    );

    testWidgets('completeFlow resolves the active flow with its value', (
      tester,
    ) async {
      final config = flowConfig();
      addTearDown(config.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: config));

      final result = config.router.run<bool>(const _Flow());
      await tester.pumpAndSettle();
      await tester.tap(find.text('confirm'));
      await tester.pumpAndSettle();

      expect(await result, isTrue);
    });

    testWidgets('dismissFlow resolves the active flow with null', (
      tester,
    ) async {
      final config = flowConfig();
      addTearDown(config.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: config));

      final result = config.router.run<bool>(const _Flow());
      await tester.pumpAndSettle();
      await tester.tap(find.text('cancel'));
      await tester.pumpAndSettle();

      expect(await result, isNull);
    });

    testWidgets('completeFlow outside a flow throws', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(() => ctx.completeFlow<bool>(true), throwsA(isA<FlutterError>()));
    });
  });

  group('KaiselBranchedShell internals', () {
    KaiselBranch<R> branch<R extends KaiselRoute>(
      KaiselRouter<R> router, {
      Widget Function(BuildContext, Widget)? scope,
    }) => KaiselBranch<R>(
      router: router,
      pageBuilder: (c, r) => const Scaffold(),
      scope: scope,
    );

    test('BranchedShellRouter.branches exposes the navigators', () {
      final a = KaiselRouter<_BranchR>(initial: const _X());
      final b = KaiselRouter<_R>(initial: const _A());
      final shell = BranchedShellRouter(branches: [a, b]);
      addTearDown(shell.dispose);
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      expect(shell.branches, [a, b]);
      expect(shell.branchCount, 2);
    });

    testWidgets('asserts the branch-widget count matches the shell', (
      tester,
    ) async {
      final a = KaiselRouter<_BranchR>(initial: const _X());
      final b = KaiselRouter<_R>(initial: const _A());
      final shell = BranchedShellRouter(branches: [a, b]);
      addTearDown(shell.dispose);
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: KaiselBranchedShell(
            shell: shell,
            branches: [branch<_BranchR>(a)], // 1 widget for 2 branches
            chromeBuilder: (c, active, content, sb) => content,
          ),
        ),
      );
      expect(tester.takeException(), isAssertionError);
    });

    testWidgets('KaiselBranch scope wraps the branch content', (tester) async {
      final a = KaiselRouter<_BranchR>(initial: const _X());
      final b = KaiselRouter<_R>(initial: const _A());
      final shell = BranchedShellRouter(branches: [a, b]);
      addTearDown(shell.dispose);
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: KaiselBranchedShell(
            shell: shell,
            branches: [
              branch<_BranchR>(
                a,
                scope: (context, child) =>
                    KeyedSubtree(key: const Key('scoped'), child: child),
              ),
              branch<_R>(b),
            ],
            chromeBuilder: (c, active, content, sb) => content,
          ),
        ),
      );
      expect(
        find.byKey(const Key('scoped'), skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('KaiselBranchSpec.adaptive builds an adaptive branch', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: KaiselBranchedShell.specs(
            branches: [
              KaiselBranchSpec<_BranchR>.adaptive(
                initial: const _X(),
                builder: (context, route, stack) => const KaiselStandalonePage(
                  Text('adaptive-x', textDirection: TextDirection.ltr),
                ),
              ),
              KaiselBranchSpec<_R>(
                initial: const _A(),
                builder: (c, r) => const Scaffold(),
              ),
            ],
            chromeBuilder: (c, active, content, sb) => content,
          ),
        ),
      );
      expect(find.text('adaptive-x'), findsOneWidget);
    });

    testWidgets('rewires when the shell instance is swapped', (tester) async {
      final a1 = KaiselRouter<_BranchR>(initial: const _X());
      final b1 = KaiselRouter<_R>(initial: const _A());
      final shell1 = BranchedShellRouter(branches: [a1, b1]);
      final a2 = KaiselRouter<_BranchR>(initial: const _X());
      final b2 = KaiselRouter<_R>(initial: const _A());
      final shell2 = BranchedShellRouter(branches: [a2, b2]);
      addTearDown(a1.dispose);
      addTearDown(b1.dispose);
      addTearDown(shell1.dispose);
      addTearDown(a2.dispose);
      addTearDown(b2.dispose);
      addTearDown(shell2.dispose);

      Widget tree(
        BranchedShellRouter shell,
        KaiselRouter<_BranchR> a,
        KaiselRouter<_R> b,
      ) => MaterialApp(
        home: KaiselBranchedShell(
          shell: shell,
          branches: [branch<_BranchR>(a), branch<_R>(b)],
          chromeBuilder: (c, active, content, sb) =>
              Text('active=$active', textDirection: TextDirection.ltr),
        ),
      );

      await tester.pumpWidget(tree(shell1, a1, b1));
      expect(find.text('active=0'), findsOneWidget);

      shell2.switchTo(1);
      // Same widget type, new shell instance → didUpdateWidget re-wires to it.
      await tester.pumpWidget(tree(shell2, a2, b2));
      await tester.pump();
      expect(find.text('active=1'), findsOneWidget);
    });

    testWidgets('back-handler pops the active branch when it has history', (
      tester,
    ) async {
      final a = KaiselRouter<_BranchR>(initial: const _X());
      final b = KaiselRouter<_R>(initial: const _A());
      final shell = BranchedShellRouter(branches: [a, b]);
      addTearDown(shell.dispose);
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: KaiselBranchedShell(
            shell: shell,
            branches: [branch<_BranchR>(a), branch<_R>(b)],
            chromeBuilder: (c, active, content, sb) => content,
          ),
        ),
      );

      await a.push(const _Y());
      await tester.pumpAndSettle();
      expect(shell.currentCanPop, isTrue);

      final popScope = tester.widget<PopScope<Object?>>(
        find.byWidgetPredicate((w) => w is PopScope),
      );
      expect(popScope.canPop, isFalse);
      final onPop = popScope.onPopInvokedWithResult;
      expect(onPop, isNotNull);
      onPop?.call(false, null);
      await tester.pumpAndSettle();

      expect(a.stack.length, 1, reason: 'back popped within the branch');
    });
  });

  group('modal flow rendering', () {
    KaiselRouterConfig<_R> flowConfig() => KaiselRouterConfig<_R>(
      initial: const _A(),
      builder: (context, route) => switch (route) {
        _A() => const Text('home', textDirection: TextDirection.ltr),
        _B() => const Text('B', textDirection: TextDirection.ltr),
        _Flow() => const Text('flow', textDirection: TextDirection.ltr),
      },
      modalBuilder: (context, flowRoute, flowChild) =>
          Material(child: flowChild),
    );

    PopScope<Object?> flowPopScope(WidgetTester tester) => tester
        .widgetList<PopScope<Object?>>(
          find.byWidgetPredicate((w) => w is PopScope),
        )
        .firstWhere((p) => !p.canPop);

    testWidgets(
      'back inside a flow pops its sub-stack, then dismisses at root',
      (tester) async {
        final config = flowConfig();
        addTearDown(config.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: config));

        final result = config.router.run<bool>(const _Flow());
        await tester.pumpAndSettle();
        expect(find.text('flow'), findsOneWidget);

        final flow = config.router.activeFlows.last;
        await flow.router.push(const _B());
        await tester.pumpAndSettle();
        expect(flow.router.stack.length, 2);

        void back() {
          final cb = flowPopScope(tester).onPopInvokedWithResult;
          expect(cb, isNotNull);
          cb?.call(false, null);
        }

        back();
        await tester.pumpAndSettle();
        expect(
          flow.router.stack.length,
          1,
          reason: 'popped the flow sub-stack',
        );

        back();
        await tester.pumpAndSettle();
        expect(await result, isNull, reason: 'flow dismissed');
      },
    );

    testWidgets(
      'an adaptive main delegate renders a flow as a standalone page',
      (tester) async {
        final config = KaiselRouterConfig<_R>.adaptive(
          initial: const _A(),
          builder: (context, route, stack) => KaiselStandalonePage(
            Text(switch (route) {
              _A() => 'A',
              _B() => 'B',
              _Flow() => 'flow-screen',
            }, textDirection: TextDirection.ltr),
          ),
          modalBuilder: (context, flowRoute, flowChild) =>
              Material(child: flowChild),
        );
        addTearDown(config.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: config));

        final result = config.router.run<bool>(const _Flow());
        await tester.pumpAndSettle();
        expect(find.text('flow-screen'), findsOneWidget);

        config.router.completeFlow<bool>(true);
        expect(await result, isTrue);
      },
    );
  });

  group('KaiselBranch.adaptive pageWrapper', () {
    testWidgets('an adaptive branch applies its pageWrapper', (tester) async {
      final a = KaiselRouter<_BranchR>(initial: const _X());
      final b = KaiselRouter<_R>(initial: const _A());
      final shell = BranchedShellRouter(branches: [a, b]);
      addTearDown(shell.dispose);
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: KaiselBranchedShell(
            shell: shell,
            branches: [
              KaiselBranch<_BranchR>.adaptive(
                router: a,
                pageBuilder: (context, route, stack) =>
                    const KaiselStandalonePage(
                      Text('x', textDirection: TextDirection.ltr),
                    ),
                pageWrapper: (ctx) => MaterialPage<Object?>(
                  key: ctx.key,
                  child: KeyedSubtree(
                    key: const Key('adaptive-wrapped'),
                    child: ctx.child,
                  ),
                ),
              ),
              KaiselBranch<_R>(
                router: b,
                pageBuilder: (c, r) => const Scaffold(),
              ),
            ],
            chromeBuilder: (c, active, content, sb) => content,
          ),
        ),
      );

      expect(
        find.byKey(const Key('adaptive-wrapped'), skipOffstage: false),
        findsOneWidget,
      );
    });
  });
}
