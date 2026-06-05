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
    });

    testWidgets('push routes by family — nearest accepting router wins', (
      tester,
    ) async {
      final main = KaiselRouter<_R>(initial: const _A());
      final branch = KaiselRouter<_BranchR>(initial: const _X());
      addTearDown(main.dispose);
      addTearDown(branch.dispose);

      // main scope above, branch scope nearer the leaf.
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
      // The platform launches the app at /b; the config's parser + provider
      // should decode it into [_B()].
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
}
