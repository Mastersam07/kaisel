import 'package:flutter/widgets.dart';
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
