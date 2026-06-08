import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';
import 'package:kaisel_core/framework.dart';

sealed class _R extends KaiselRoute {
  const _R();
}

final class _Home extends _R {
  const _Home();
}

final class _Detail extends _R {
  const _Detail(this.id);

  final String id;

  @override
  List<Object?> get props => <Object?>[id];
}

// Has a field but no `props` override — the missing-props bug.
final class _NoProps extends _R {
  const _NoProps(this.id);

  final String id;
}

class _Codec implements KaiselConfigCodec<_R> {
  const _Codec();

  @override
  Uri encode(KaiselConfig<_R> config) => switch (config.mainStack.last) {
    _Home() => Uri(path: '/'),
    _Detail(:final id) => Uri(path: '/detail/$id'),
    _NoProps(:final id) => Uri(path: '/np/$id'),
  };

  @override
  KaiselConfig<_R>? decode(Uri uri) => null;
}

// Decodes a few URLs back to real configs, for the deep-link preview.
class _RoundTripCodec implements KaiselConfigCodec<_R> {
  const _RoundTripCodec();

  @override
  Uri encode(KaiselConfig<_R> config) => Uri(path: '/');

  @override
  KaiselConfig<_R>? decode(Uri uri) => switch (uri.pathSegments) {
    ['detail', final id] => KaiselConfig(
      mainStack: <_R>[const _Home(), _Detail(id)],
    ),
    ['shell'] => KaiselConfig(
      mainStack: const <_R>[_Home()],
      nestedState: KaiselShellConfig(
        activeBranch: 1,
        activeBranchStack: const <KaiselRoute>[_Home()],
      ),
    ),
    ['module'] => KaiselConfig(
      mainStack: const <_R>[_Home()],
      nestedState: KaiselModuleConfig(stack: const <KaiselRoute>[_Home()]),
    ),
    _ => null,
  };
}

class _ThrowingCodec implements KaiselConfigCodec<_R> {
  const _ThrowingCodec();

  @override
  Uri encode(KaiselConfig<_R> config) => throw StateError('boom');

  @override
  KaiselConfig<_R>? decode(Uri uri) => null;
}

// A nested handle that looks like a mounted module (configType + stack).
class _FakeModuleHandle implements KaiselNestedHandle {
  @override
  Type get configType => KaiselModuleConfig;

  @override
  KaiselNestedConfig captureConfig() =>
      KaiselModuleConfig(stack: const <KaiselRoute>[_Home()]);

  @override
  Future<void> restoreFromConfig(KaiselNestedConfig config) async {}

  @override
  void addListener(void Function() listener) {}

  @override
  void removeListener(void Function() listener) {}
}

KaiselRouterDelegate<_R> _delegate(KaiselRouter<_R> router) =>
    KaiselRouterDelegate<_R>(
      router: router,
      builder: (_, _) => const SizedBox.shrink(),
    );

void main() {
  test('debugSnapshot reflects the main stack and updates on push', () async {
    final router = KaiselRouter<_R>(initial: const _Home());
    final delegate = _delegate(router);

    final before = delegate.debugSnapshot();
    expect(before.main.depth, 1);
    expect(before.main.canPop, isFalse);
    expect(before.main.entries.single.type, '_Home');
    expect(before.main.entries.single.props, isEmpty);

    await router.push(const _Detail('a'));

    final after = delegate.debugSnapshot();
    expect(after.main.depth, 2);
    expect(after.main.canPop, isTrue);
    expect(after.main.entries.last.type, '_Detail');
    expect(after.main.entries.last.props, <String>['a']);
    expect(after.main.entries.last.label, '_Detail(a)');
    // The bottom entry keeps its identity-stable id across the push.
    expect(after.main.entries.first.id, before.main.entries.first.id);

    delegate.dispose();
    router.dispose();
  });

  test('debugSnapshot includes a registered branched shell', () {
    final router = KaiselRouter<_R>(initial: const _Home());
    final delegate = _delegate(router);

    final homeBranch = KaiselRouter<_R>(initial: const _Home());
    final detailBranch = KaiselRouter<_R>(initial: const _Detail('x'));
    final shell = BranchedShellRouter(
      branches: <KaiselNavigator>[homeBranch, detailBranch],
      initialBranch: 1,
    );
    delegate.registerNested(shell);

    final snap = delegate.debugSnapshot();
    expect(snap.branches, hasLength(1));
    final shellSnap = snap.branches.single;
    expect(shellSnap.branchCount, 2);
    expect(shellSnap.activeBranch, 1);
    expect(shellSnap.branches[1].stack.entries.single.label, '_Detail(x)');

    delegate.dispose();
    shell.dispose();
    router.dispose();
    homeBranch.dispose();
    detailBranch.dispose();
  });

  test('debugSnapshot marks absorbed entries from the router', () {
    final router = KaiselRouter<_R>.fromStack(const <_R>[
      _Home(),
      _Detail('a'),
    ]);
    final delegate = _delegate(router);
    // Simulate an adaptive build that collapsed position 0 (the master).
    router.debugSetAbsorbedPositions(const <int>{0});
    final entries = delegate.debugSnapshot().main.entries;
    expect(entries[0].absorbed, isTrue);
    expect(entries[1].absorbed, isFalse);
    delegate.dispose();
    router.dispose();
  });

  testWidgets('an adaptive build records the absorbed master entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = KaiselRouter<_R>.fromStack(const <_R>[
      _Home(),
      _Detail('a'),
    ]);
    final delegate = KaiselRouterDelegate<_R>.adaptive(
      router: router,
      builder: (context, route, ctx) {
        final wide = MediaQuery.sizeOf(context).width >= 600;
        return switch ((ctx.previous, route, wide)) {
          (_Home(), _Detail(), true) => const KaiselAbsorbingPage(
            widget: SizedBox.shrink(),
            absorbing: 1,
          ),
          _ => const KaiselStandalonePage(SizedBox.shrink()),
        };
      },
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));

    final entries = delegate.debugSnapshot().main.entries;
    expect(entries[0].absorbed, isTrue, reason: 'Home (master) is absorbed');
    expect(entries[1].absorbed, isFalse, reason: 'Detail (top) is not');

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });

  test('debugSnapshot surfaces the last guard run', () async {
    final router = KaiselRouter<_R>(
      initial: const _Home(),
      guards: <KaiselGuard<_R>>[
        (current, proposed) => proposed.last is _Detail
            ? <_R>[...proposed, const _Home()]
            : proposed,
      ],
    );
    final delegate = _delegate(router);

    expect(delegate.debugSnapshot().guardTrace, isNull);

    await router.push(const _Detail('z'));

    final trace = delegate.debugSnapshot().guardTrace;
    expect(trace, isNotNull);
    expect(trace!.input, <String>['_Home', '_Detail(z)']);
    expect(trace.output, <String>['_Home', '_Detail(z)', '_Home']);
    expect(trace.steps.single.changed, isTrue);

    delegate.dispose();
    router.dispose();
  });

  test(
    'debugSnapshot encodes the current url when a codec is supplied',
    () async {
      final router = KaiselRouter<_R>(initial: const _Home());
      final delegate = KaiselRouterDelegate<_R>(
        router: router,
        builder: (_, _) => const SizedBox.shrink(),
        codec: const _Codec(),
      );

      expect(delegate.debugSnapshot().url, '/');
      await router.push(const _Detail('a'));
      expect(delegate.debugSnapshot().url, '/detail/a');

      delegate.dispose();
      router.dispose();
    },
  );

  test('url is null without a codec', () {
    final router = KaiselRouter<_R>(initial: const _Home());
    final delegate = _delegate(router);
    expect(delegate.debugSnapshot().url, isNull);
    expect(delegate.debugSnapshot().problems, isEmpty);
    delegate.dispose();
    router.dispose();
  });

  test('debugSnapshot flags a broken codec round-trip', () {
    final router = KaiselRouter<_R>(initial: const _Home());
    // _Codec.encode works but its decode always returns null — the current
    // state encodes to a URL that won't decode back.
    final delegate = KaiselRouterDelegate<_R>(
      router: router,
      builder: (_, _) => const SizedBox.shrink(),
      codec: const _Codec(),
    );
    final problems = delegate.debugSnapshot().problems;
    expect(problems.any((p) => p.kind == 'codec'), isTrue);
    delegate.dispose();
    router.dispose();
  });

  test('a throwing codec is reported as a problem, not crashed', () {
    final router = KaiselRouter<_R>(initial: const _Home());
    final delegate = KaiselRouterDelegate<_R>(
      router: router,
      builder: (_, _) => const SizedBox.shrink(),
      codec: const _ThrowingCodec(),
    );
    expect(delegate.debugSnapshot().url, isNull);
    expect(
      delegate.debugSnapshot().problems.any((p) => p.kind == 'codec'),
      isTrue,
    );
    delegate.dispose();
    router.dispose();
  });

  test('debugSnapshot includes a mounted module', () {
    final router = KaiselRouter<_R>(initial: const _Home());
    final delegate = _delegate(router);
    delegate.registerNested(_FakeModuleHandle());

    final modules = delegate.debugSnapshot().modules;
    expect(modules, hasLength(1));
    expect(modules.single.routeType, '_Home');
    expect(modules.single.stack.entries.single.label, '_Home');

    delegate.dispose();
    router.dispose();
  });

  test('debugDecode previews a decoded URL without navigating', () {
    final router = KaiselRouter<_R>(initial: const _Home());
    final delegate = KaiselRouterDelegate<_R>(
      router: router,
      builder: (_, _) => const SizedBox.shrink(),
      codec: const _RoundTripCodec(),
    );

    expect(delegate.debugDecode('/detail/x'), <String>[
      'main: _Home → _Detail(x)',
    ]);
    expect(delegate.debugDecode('/shell'), contains('shell: branch 1 → _Home'));
    expect(delegate.debugDecode('/module'), contains('module: _Home'));
    expect(delegate.debugDecode('/nope'), isNull);
    // Previewing does not navigate.
    expect(router.stack, const <_R>[_Home()]);

    delegate.dispose();
    router.dispose();
  });

  test('debugDecode is null without a codec', () {
    final router = KaiselRouter<_R>(initial: const _Home());
    final delegate = _delegate(router);
    expect(delegate.debugDecode('/x'), isNull);
    delegate.dispose();
    router.dispose();
  });

  test('debugSnapshot reports a branch no-op mutation as a problem', () async {
    final router = KaiselRouter<_R>(initial: const _Home());
    final delegate = _delegate(router);
    final branch = KaiselRouter<_R>(initial: const _Home());
    final shell = BranchedShellRouter(branches: <KaiselNavigator>[branch]);
    delegate.registerNested(shell);

    await branch.push(const _NoProps('a'));
    expect(delegate.debugSnapshot().problems, isEmpty);

    // _NoProps('a') == _NoProps('b') (no props), so this is a no-op.
    await branch.pushOrReplaceTop(const _NoProps('b'));

    final problems = delegate.debugSnapshot().problems;
    expect(problems, hasLength(1));
    expect(problems.single.kind, 'noOp');
    expect(problems.single.router, contains('branch'));

    delegate.dispose();
    shell.dispose();
    router.dispose();
    branch.dispose();
  });

  test('registers with the inspector in debug and deregisters on dispose', () {
    final inspector = KaiselInspector.instance;
    final before = inspector.snapshot().roots.length;

    final router = KaiselRouter<_R>(initial: const _Home());
    final delegate = _delegate(router);
    // kDebugMode is true under flutter test, so creation registers a root.
    expect(inspector.snapshot().roots.length, before + 1);

    delegate.dispose();
    router.dispose();
    expect(inspector.snapshot().roots.length, before);
  });
}
