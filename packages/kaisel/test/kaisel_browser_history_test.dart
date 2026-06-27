import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

sealed class _R extends KaiselRoute {
  const _R();
}

final class _Home extends _R {
  const _Home();
}

final class _A extends _R {
  const _A();
}

final class _B extends _R {
  const _B();
}

class _Codec implements KaiselStackCodec<_R> {
  const _Codec();
  @override
  Uri encode(List<_R> stack) => switch (stack.last) {
    _Home() => Uri(path: '/'),
    _A() => Uri(path: '/a'),
    _B() => Uri(path: '/b'),
  };
  @override
  List<_R>? decode(Uri uri) => switch (uri.pathSegments) {
    [] || [''] => const [_Home()],
    ['a'] => const [_Home(), _A()],
    ['b'] => const [_Home(), _B()],
    _ => null,
  };
}

void main() {
  testWidgets(
    'push adds a browser history entry; replaceTop and set replace it',
    (tester) async {
      final updates = <Map<Object?, Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.navigation,
        (call) async {
          if (call.method == 'routeInformationUpdated') {
            updates.add((call.arguments as Map).cast<Object?, Object?>());
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.navigation,
          null,
        ),
      );

      final config = KaiselRouterConfig<_R>(
        initial: const _Home(),
        builder: (_, _) => const SizedBox.shrink(),
        codec: const StackToConfigCodec<_R>(_Codec()),
        fallback: const [_Home()],
      );
      addTearDown(config.router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: config));
      await tester.pumpAndSettle();

      String uriOf(Map<Object?, Object?> u) => '${u['uri'] ?? u['location']}';

      updates.clear();
      await config.router.push(const _A());
      await tester.pumpAndSettle();
      expect(uriOf(updates.last), '/a');
      expect(
        updates.last['replace'],
        isFalse,
        reason: 'a push to a new URL adds a browser history entry',
      );

      updates.clear();
      await config.router.replaceTop(const _B());
      await tester.pumpAndSettle();
      expect(uriOf(updates.last), '/b');
      expect(
        updates.last['replace'],
        isTrue,
        reason: 'replaceTop overwrites the current history entry',
      );

      updates.clear();
      await config.router.set(const [_Home(), _A()]);
      await tester.pumpAndSettle();
      expect(uriOf(updates.last), '/a');
      expect(
        updates.last['replace'],
        isTrue,
        reason: 'set overwrites the current history entry',
      );

      await config.router.push(const _B());
      await tester.pumpAndSettle();
      updates.clear();
      await config.router.pop();
      await tester.pumpAndSettle();
      expect(uriOf(updates.last), '/a');
      expect(
        updates.last['replace'],
        isTrue,
        reason:
            'a programmatic pop overwrites the entry it returns to rather '
            'than leaving the popped screen reachable via forward',
      );
    },
  );

  testWidgets('an inbound URL (browser back/forward, deep link) restores the '
      'stack via the codec', (tester) async {
    final config = KaiselRouterConfig<_R>(
      initial: const _Home(),
      builder: (_, _) => const SizedBox.shrink(),
      codec: const StackToConfigCodec<_R>(_Codec()),
      fallback: const [_Home()],
    );
    addTearDown(config.router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: config));
    await tester.pumpAndSettle();

    // Deliver a URL the way the platform does on browser back/forward.
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(
        const MethodCall('pushRouteInformation', <String, Object?>{
          'location': '/a',
          'state': null,
        }),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(config.router.stack, [const _Home(), const _A()]);
  });
}
