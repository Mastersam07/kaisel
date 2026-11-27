// Regression test for https://github.com/Mastersam07/kaisel/issues/114.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

sealed class _AppRoute extends KaiselRoute {
  const _AppRoute();
}

final class _LoginMount extends _AppRoute {
  const _LoginMount();
}

final class _HomeMount extends _AppRoute {
  const _HomeMount();
}

sealed class _LoginRoute extends KaiselRoute {
  const _LoginRoute();
}

final class _LoginForm extends _LoginRoute {
  const _LoginForm();
}

sealed class _HomeRoute extends KaiselRoute {
  const _HomeRoute();
}

final class _HomeList extends _HomeRoute {
  const _HomeList();
}

class _LoginModule extends RouteModule<_LoginRoute> {
  const _LoginModule();

  @override
  List<_LoginRoute> get initialStack => const [_LoginForm()];

  @override
  Widget buildPage(BuildContext context, _LoginRoute route) =>
      const Text('login');
}

class _LoginCodec extends ModuleStackCodec<_LoginRoute> {
  const _LoginCodec();

  @override
  List<String> encode(List<_LoginRoute> stack) => switch (stack.last) {
    _LoginForm() => const [],
  };

  @override
  List<_LoginRoute>? decode(List<String> segments) =>
      segments.isEmpty ? const [_LoginForm()] : null;
}

class _HomeModule extends RouteModule<_HomeRoute> {
  const _HomeModule();

  @override
  List<_HomeRoute> get initialStack => const [_HomeList()];

  @override
  Widget buildPage(BuildContext context, _HomeRoute route) =>
      const Text('home');
}

class _HomeCodec extends ModuleStackCodec<_HomeRoute> {
  const _HomeCodec();

  @override
  List<String> encode(List<_HomeRoute> stack) => switch (stack.last) {
    _HomeList() => const [],
  };

  @override
  List<_HomeRoute>? decode(List<String> segments) =>
      segments.isEmpty ? const [_HomeList()] : null;
}

class _NoBaseRoutes implements KaiselStackCodec<_AppRoute> {
  const _NoBaseRoutes();

  @override
  Uri encode(List<_AppRoute> stack) => Uri(path: '/');

  @override
  List<_AppRoute>? decode(Uri uri) => null;
}

void main() {
  testWidgets('a guard redirect between two module mounts reports no error', (
    tester,
  ) async {
    final signedIn = ValueNotifier(false);
    addTearDown(signedIn.dispose);
    final config = KaiselRouterConfig<_AppRoute>(
      initial: const _HomeMount(),
      builder: (context, route) => switch (route) {
        _LoginMount() => const KaiselModuleMount(module: _LoginModule()),
        _HomeMount() => const KaiselModuleMount(module: _HomeModule()),
      },
      codec: const ConfigCodecWithModules<_AppRoute>(
        baseCodec: StackToConfigCodec(_NoBaseRoutes()),
        modules: [
          ModuleMount(
            mountRoute: _LoginMount(),
            prefix: '/login',
            codec: _LoginCodec(),
          ),
          ModuleMount(
            mountRoute: _HomeMount(),
            prefix: '/home',
            codec: _HomeCodec(),
          ),
        ],
      ),
      guards: [
        (current, proposed) {
          final atLogin = proposed.last is _LoginMount;
          if (!signedIn.value) {
            return atLogin ? proposed : const [_LoginMount()];
          }
          return atLogin ? const [_HomeMount()] : proposed;
        },
      ],
      reevaluateOn: signedIn,
    );
    addTearDown(config.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: config));
    await tester.pumpAndSettle();
    expect(find.text('login'), findsOneWidget);
    expect(config.routeInformationProvider!.value.uri.path, '/login');

    signedIn.value = true;
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(config.routeInformationProvider!.value.uri.path, '/home');
  });
}
