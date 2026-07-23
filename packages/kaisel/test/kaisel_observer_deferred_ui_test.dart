import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// A flow's inner navigator mounts during build and dispatches its initial
// observer notifications right there. This pins the pattern the docs
// recommend for observers feeding widget-bound state (how-to/track-screens):
// defer with a microtask, which can never run mid-build.

sealed class _App extends KaiselRoute {
  const _App();
}

final class _Home extends _App {
  const _Home();
}

final class _Flow extends _App implements KaiselModalRoute<void> {
  const _Flow();
}

final _log = ValueNotifier<List<String>>(const []);

class _UiBoundObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name case final name?) _add('→ $name');
  }

  void _add(String entry) =>
      scheduleMicrotask(() => _log.value = [..._log.value, entry]);
}

void main() {
  testWidgets('deferred UI-bound observer survives a flow mounting', (
    tester,
  ) async {
    _log.value = const [];
    final router = KaiselRouter<_App>(initial: const _Home());
    final delegate = KaiselRouterDelegate<_App>(
      router: router,
      observers: () => [_UiBoundObserver()],
      builder: (context, route) => switch (route) {
        _Home() => Scaffold(
          body: ValueListenableBuilder<List<String>>(
            valueListenable: _log,
            builder: (context, entries, _) => Text('log:${entries.length}'),
          ),
        ),
        _Flow() => const Text('flow-content'),
      },
      modalBuilder: (context, route, child) => Center(child: child),
    );
    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));

    unawaited(router.run<void>(const _Flow()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('flow-content'), findsOneWidget);
    expect(_log.value, contains('→ _Flow'));
  });
}
