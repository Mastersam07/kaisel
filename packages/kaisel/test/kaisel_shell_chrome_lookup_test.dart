import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

sealed class _AppRoute extends KaiselRoute {
  const _AppRoute();
}

final class _Host extends _AppRoute {
  const _Host();
}

sealed class _TabRoute extends KaiselRoute {
  const _TabRoute();
}

final class _TabRoot extends _TabRoute {
  const _TabRoot();
}

final class _TabDetail extends _TabRoute {
  const _TabDetail();
}

Future<BuildContext> _pumpChrome(WidgetTester tester) async {
  late BuildContext chrome;
  final router = KaiselRouter<_AppRoute>(initial: const _Host());
  addTearDown(router.dispose);
  final delegate = KaiselRouterDelegate<_AppRoute>(
    router: router,
    builder: (context, route) => KaiselBranchedShell.specs(
      branches: [
        KaiselBranchSpec<_TabRoute>(
          initial: const _TabRoot(),
          builder: (context, route) => Text('$route'),
        ),
      ],
      chromeBuilder: (context, active, content, switchBranch) {
        chrome = context;
        return content;
      },
    ),
  );
  addTearDown(delegate.dispose);
  await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
  return chrome;
}

Matcher _chromeError() => isA<FlutterError>().having(
  (e) => e.message,
  'message',
  allOf(contains('inside a shell chromeBuilder'), contains('context.shell()')),
);

void main() {
  testWidgets('a typed branch lookup in the chrome names the fix', (
    tester,
  ) async {
    final chrome = await _pumpChrome(tester);

    expect(() => chrome.router<_TabRoute>(), throwsA(_chromeError()));
    expect(chrome.router<_AppRoute>(), isA<KaiselRouter<_AppRoute>>());
  });

  testWidgets('pushing a branch route from the chrome names the fix', (
    tester,
  ) async {
    final chrome = await _pumpChrome(tester);

    expect(() => chrome.push(const _TabDetail()), throwsA(_chromeError()));
  });

  testWidgets('the suggested fix adds to the active branch', (tester) async {
    final chrome = await _pumpChrome(tester);

    final current = chrome.shell().current;
    await current.set([...current.stack, const _TabDetail()]);
    await tester.pumpAndSettle();

    expect(current.stack, const [_TabRoot(), _TabDetail()]);
  });
}
