import 'package:kaisel_core/kaisel_core.dart';
import 'package:test/test.dart';

sealed class _R extends KaiselRoute {
  const _R();
}

final class _Home extends _R {
  const _Home();
}

final class _Login extends _R {
  const _Login();
}

final class _Settings extends _R {
  const _Settings();
}

final class _Step extends _R {
  const _Step(this.n);
  final int n;
  @override
  List<Object?> get props => [n];
}

final class _Flow extends _R implements KaiselModalRoute<String> {
  const _Flow();
}

final class _Inner extends _R implements KaiselModalRoute<int> {
  const _Inner();
}

void main() {
  group('main stack redirect with an open flow', () {
    late bool signedIn;
    late KaiselRouter<_R> router;

    List<_R> authGuard(List<_R> current, List<_R> proposed) =>
        signedIn ? proposed : const [_Login()];

    setUp(() {
      signedIn = true;
      router = KaiselRouter<_R>(initial: const _Home(), guards: [authGuard]);
    });

    tearDown(() => router.dispose());

    test('closes the flow with null when reevaluate redirects', () async {
      final result = router.run(const _Flow());
      expect(router.hasActiveFlow, isTrue);

      signedIn = false;
      await router.reevaluate();

      expect(await result, isNull);
      expect(router.hasActiveFlow, isFalse);
      expect(router.stack, const [_Login()]);
    });

    test('closes every nested flow', () async {
      final outer = router.run(const _Flow());
      final inner = router.run(const _Inner());
      expect(router.activeFlows, hasLength(2));

      signedIn = false;
      await router.reevaluate();

      expect(await inner, isNull);
      expect(await outer, isNull);
      expect(router.hasActiveFlow, isFalse);
    });

    test('closes the flow when a push is redirected', () async {
      final result = router.run(const _Flow());

      signedIn = false;
      await router.push(const _Settings());

      expect(await result, isNull);
      expect(router.stack, const [_Login()]);
    });

    test('keeps the flow open when nothing is redirected', () async {
      final result = router.run(const _Flow());

      await router.push(const _Settings());
      await router.reevaluate();

      expect(router.hasActiveFlow, isTrue);
      expect(router.stack, const [_Home(), _Settings()]);

      router.completeFlow<String>('done');
      expect(await result, 'done');
    });

    test('keeps the flow open when a guard refuses the change', () async {
      final refusing = KaiselRouter<_R>(
        initial: const _Home(),
        guards: [(current, proposed) => current],
      );
      addTearDown(refusing.dispose);
      refusing.run(const _Flow()).ignore();

      await refusing.push(const _Settings());

      expect(refusing.hasActiveFlow, isTrue);
      expect(refusing.stack, const [_Home()]);
    });

    test('a redirect by a flow guard does not close the flow', () async {
      final result = router.run(
        const _Flow(),
        flowGuards: [
          (current, proposed) => proposed.last == const _Step(1)
              ? [...current, const _Step(2)]
              : proposed,
        ],
      );
      final flowRouter = router.activeFlows.last.router;

      await flowRouter.push(const _Step(1));

      expect(router.hasActiveFlow, isTrue);
      expect(flowRouter.stack, const [_Flow(), _Step(2)]);

      router.completeFlow<String>('done');
      expect(await result, 'done');
    });
  });
}
