import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

sealed class _R extends KaiselRoute {
  const _R();
}

final class _Home extends _R {
  const _Home();
}

final class _Vault extends _R {
  const _Vault();
}

final class _Locked extends _R {
  const _Locked();
}

class _EntitlementCodec extends KaiselStackCodec<_R> {
  const _EntitlementCodec(this.hasEntitlement);

  final Future<bool> Function() hasEntitlement;

  @override
  Uri encode(List<_R> stack) => switch (stack.last) {
    _Home() => Uri(path: '/'),
    _Vault() => Uri(path: '/vault'),
    _Locked() => Uri(path: '/locked'),
  };

  @override
  Future<List<_R>?> decode(Uri uri) async => switch (uri.pathSegments) {
    [] || [''] => const [_Home()],
    ['vault'] =>
      await hasEntitlement()
          ? const [_Home(), _Vault()]
          : const [_Home(), _Locked()],
    _ => null,
  };
}

class _SyncCodec extends KaiselStackCodec<_R> {
  const _SyncCodec();

  @override
  Uri encode(List<_R> stack) => Uri(path: '/');

  @override
  List<_R>? decode(Uri uri) =>
      uri.path == '/vault' ? const [_Home(), _Vault()] : const [_Home()];
}

RouteInformationParser<KaiselConfig<_R>> _parserOf(
  KaiselRouterConfig<_R> config,
) => config.routeInformationParser as RouteInformationParser<KaiselConfig<_R>>;

Widget _appWith(KaiselRouterConfig<_R> config) =>
    MaterialApp.router(routerConfig: config);

KaiselRouterConfig<_R> _configWith(KaiselStackCodec<_R> codec) =>
    KaiselRouterConfig<_R>(
      initial: const _Home(),
      codec: StackToConfigCodec(codec),
      builder: (context, route) => switch (route) {
        _Home() => const Scaffold(body: Text('home')),
        _Vault() => const Scaffold(body: Text('vault')),
        _Locked() => const Scaffold(body: Text('locked')),
      },
    );

void main() {
  testWidgets('an async codec resolves a deep link once its state is read', (
    tester,
  ) async {
    final gate = Completer<bool>();
    final config = _configWith(_EntitlementCodec(() => gate.future));
    await tester.pumpWidget(_appWith(config));

    final pending = _parserOf(
      config,
    ).parseRouteInformation(RouteInformation(uri: Uri.parse('/vault')));
    gate.complete(true);

    expect((await pending).mainStack, const [_Home(), _Vault()]);
  });

  testWidgets('the async result decides the destination', (tester) async {
    final config = _configWith(_EntitlementCodec(() async => false));
    await tester.pumpWidget(_appWith(config));

    final decoded = await _parserOf(
      config,
    ).parseRouteInformation(RouteInformation(uri: Uri.parse('/vault')));

    expect(decoded.mainStack, const [_Home(), _Locked()]);
  });

  testWidgets('an unrecognised URL still falls back', (tester) async {
    final config = _configWith(_EntitlementCodec(() async => true));
    await tester.pumpWidget(_appWith(config));

    final decoded = await _parserOf(
      config,
    ).parseRouteInformation(RouteInformation(uri: Uri.parse('/nope')));

    expect(decoded.mainStack, const [_Home()]);
  });

  testWidgets('synchronous codecs are unaffected', (tester) async {
    final config = _configWith(const _SyncCodec());
    await tester.pumpWidget(_appWith(config));

    final decoded = await _parserOf(
      config,
    ).parseRouteInformation(RouteInformation(uri: Uri.parse('/vault')));

    expect(decoded.mainStack, const [_Home(), _Vault()]);
  });
}
