import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaisel/kaisel.dart';

sealed class _AppRoute extends KaiselRoute {
  const _AppRoute();
}

final class _Login extends _AppRoute {
  const _Login();
}

final class _ShellHost extends _AppRoute {
  const _ShellHost();
}

sealed class _HomeRoute extends KaiselRoute {
  const _HomeRoute();
}

final class _HomeRoot extends _HomeRoute {
  const _HomeRoot();
}

sealed class _ProductRoute extends KaiselRoute {
  const _ProductRoute();
}

final class _ProductList extends _ProductRoute {
  const _ProductList();
}

final class _ProductDetail extends _ProductRoute {
  const _ProductDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

class _Auth {
  bool signedIn = false;
}

class _ShellHostWidget extends StatefulWidget {
  const _ShellHostWidget();
  @override
  State<_ShellHostWidget> createState() => _ShellHostWidgetState();
}

class _ShellHostWidgetState extends State<_ShellHostWidget> {
  late final KaiselRouter<_HomeRoute> _home = KaiselRouter<_HomeRoute>(
    initial: const _HomeRoot(),
  );
  late final KaiselRouter<_ProductRoute> _products =
      KaiselRouter<_ProductRoute>(initial: const _ProductList());
  late final BranchedShellRouter _shell = BranchedShellRouter(
    branches: [_home, _products],
  );

  @override
  void dispose() {
    _shell.dispose();
    _home.dispose();
    _products.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KaiselBranchedShell(
    shell: _shell,
    branches: [
      KaiselBranch<_HomeRoute>(
        router: _home,
        pageBuilder: (context, route) => const Scaffold(body: Text('home')),
      ),
      KaiselBranch<_ProductRoute>(
        router: _products,
        pageBuilder: (context, route) => switch (route) {
          _ProductList() => const Scaffold(body: Text('product list')),
          _ProductDetail(:final id) => Scaffold(body: Text('detail $id')),
        },
      ),
    ],
    chromeBuilder: (context, active, branchContent, switchBranch) =>
        Scaffold(body: branchContent),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a guarded shell deep link survives the login detour', (
    tester,
  ) async {
    final auth = _Auth();
    final mainRouter = KaiselRouter<_AppRoute>(
      initial: const _Login(),
      guards: [
        (current, proposed) =>
            !auth.signedIn && proposed.any((r) => r is _ShellHost)
            ? [const _Login()]
            : proposed,
      ],
    );
    final delegate = KaiselRouterDelegate<_AppRoute>(
      router: mainRouter,
      builder: (context, route) => switch (route) {
        _Login() => const Scaffold(body: Text('login')),
        _ShellHost() => const _ShellHostWidget(),
      },
    );
    addTearDown(delegate.dispose);
    addTearDown(mainRouter.dispose);

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    await tester.pumpAndSettle();
    expect(find.text('login'), findsOneWidget);

    // The deep link arrives while signed out. The guard rewrites the main
    // stack to Login; the shell never mounts, so nothing consumes the
    // nested state.
    await delegate.setNewRoutePath(
      KaiselConfig<_AppRoute>(
        mainStack: [const _ShellHost()],
        nestedState: KaiselShellConfig(
          activeBranch: 1,
          activeBranchStack: const [_ProductList(), _ProductDetail('42')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('login'), findsOneWidget);
    expect(mainRouter.stack, [const _Login()]);

    // Sign in and go where the guard would have allowed all along.
    auth.signedIn = true;
    await mainRouter.set([const _ShellHost()]);
    await tester.pumpAndSettle();

    expect(find.text('detail 42'), findsOneWidget);
  });

  testWidgets('an abandoned nested deep link does not fire later', (
    tester,
  ) async {
    final auth = _Auth()..signedIn = true;
    final mainRouter = KaiselRouter<_AppRoute>(
      initial: const _Login(),
      guards: [
        (current, proposed) =>
            !auth.signedIn && proposed.any((r) => r is _ShellHost)
            ? [const _Login()]
            : proposed,
      ],
    );
    final delegate = KaiselRouterDelegate<_AppRoute>(
      router: mainRouter,
      builder: (context, route) => switch (route) {
        _Login() => const Scaffold(body: Text('login')),
        _ShellHost() => const _ShellHostWidget(),
      },
    );
    addTearDown(delegate.dispose);
    addTearDown(mainRouter.dispose);

    await tester.pumpWidget(MaterialApp.router(routerDelegate: delegate));
    await tester.pumpAndSettle();

    auth.signedIn = false;
    await delegate.setNewRoutePath(
      KaiselConfig<_AppRoute>(
        mainStack: [const _ShellHost()],
        nestedState: KaiselShellConfig(
          activeBranch: 1,
          activeBranchStack: const [_ProductList(), _ProductDetail('42')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The user abandons the link entirely: signs in, then opens the shell
    // from the app's own UI. They expect the shell's default branch.
    auth.signedIn = true;
    await delegate.setNewRoutePath(
      KaiselConfig<_AppRoute>(mainStack: [const _ShellHost()]),
    );
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
  });
}
