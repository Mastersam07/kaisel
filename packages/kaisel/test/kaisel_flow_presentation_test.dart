import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

// A pageWrapper can give a flow its own entrance by branching on
// KaiselPageWrapperContext.isFlow (Option C, phase 4). Without one, the flow
// falls back to the framework's instant, transparent page.

sealed class _App extends KaiselRoute {
  const _App();
}

final class _Home extends _App {
  const _Home();
}

final class _Flow extends _App implements KaiselModalRoute<void> {
  const _Flow();
}

class _RecordingObserver extends NavigatorObserver {
  final List<String> pushed = <String>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name case final name?) pushed.add(name);
  }
}

/// A transparent flow page that also paints a marker, so a test can tell the
/// wrapper was consulted for the flow's outer page. Forwards name/arguments so
/// the flow stays identifiable to observers.
class _MarkerFlowPage extends Page<Object?> {
  const _MarkerFlowPage({
    required LocalKey super.key,
    required this.child,
    super.name,
    super.arguments,
  });

  final Widget child;

  @override
  Route<Object?> createRoute(BuildContext context) {
    return PageRouteBuilder<Object?>(
      settings: this,
      opaque: false,
      maintainState: true,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => Stack(
        textDirection: TextDirection.ltr,
        children: [
          child,
          const Positioned(
            left: 0,
            top: 0,
            child: Text('wrapped-flow', textDirection: TextDirection.ltr),
          ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('a pageWrapper customises the flow outer page via isFlow', (
    tester,
  ) async {
    final isFlowSeen = <bool>[];
    final created = <_RecordingObserver>[];
    final router = KaiselRouter<_App>(initial: const _Home());
    final delegate = KaiselRouterDelegate<_App>(
      router: router,
      observers: () {
        final observer = _RecordingObserver();
        created.add(observer);
        return [observer];
      },
      pageWrapper: (ctx) {
        isFlowSeen.add(ctx.isFlow);
        if (ctx.isFlow) {
          // A custom flow page forwards name/arguments from ctx.route so the
          // flow stays identifiable to observers (the framework can't inject
          // them into a user-built page).
          return _MarkerFlowPage(
            key: ctx.key,
            name: ctx.route.routeName,
            arguments: ctx.route,
            child: ctx.child,
          );
        }
        return MaterialPage<Object?>(key: ctx.key, child: ctx.child);
      },
      builder: (context, route) => switch (route) {
        _Home() => const Scaffold(body: Center(child: Text('home'))),
        _Flow() => const Scaffold(body: Center(child: Text('flow'))),
      },
      modalBuilder: (context, route, flowContent) => flowContent,
    );

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    final mainObserver = created.first;
    // Main page only: the wrapper sees a non-flow context.
    expect(isFlowSeen, isNotEmpty);
    expect(isFlowSeen.every((flag) => flag == false), isTrue);

    final result = router.run<void>(const _Flow());
    await tester.pumpAndSettle();

    // The wrapper was consulted for the flow's outer page (isFlow: true) and
    // its custom page is on screen alongside the flow content.
    expect(isFlowSeen, contains(true));
    expect(find.text('wrapped-flow'), findsOneWidget);
    expect(find.text('flow'), findsOneWidget);
    // Because the custom page forwarded name/arguments, the observer still
    // sees the flow boundary.
    expect(mainObserver.pushed, contains('_Flow'));

    // The tagged key is preserved, so the flow still dismisses normally.
    router.dismissFlow();
    await result;
    await tester.pumpAndSettle();
    expect(router.hasActiveFlow, isFalse);
    expect(find.text('wrapped-flow'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    delegate.dispose();
    router.dispose();
  });
}
