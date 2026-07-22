// Typed results + flows-as-routes demo for the kaisel router.
//
// Run from the `example/` directory:
//
//   flutter run -t lib/main_results_and_flows.dart
//
// What this shows
// ---------------
// 1. `context.pushForResult<T>(...)` — "Pick accent colour" pushes a normal
//    screen on the MAIN stack and awaits a typed result. The picker returns a
//    value with `context.pop(value)`; Home shows it.
//
// 2. A modal flow rendered as a route — "Edit profile" opens a `run<bool>`
//    flow. Because the flow is a route on the main navigator:
//      - "Show help" opens a `showDialog` that renders ABOVE the flow (it would
//        land behind it under a separate-navigator model);
//      - the app's shared `RouteObserver` sees the flow open and close — watch
//        the "Navigation log" panel on Home record both the picker and the
//        flow boundary.
//
// 3. A custom flow entrance via `pageWrapper` — branching on
//    `KaiselPageWrapperContext.isFlow`, the flow slides up instead of appearing
//    instantly. The custom page forwards `name`/`arguments` so it stays
//    observable.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kaisel/kaisel.dart';

sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

final class Home extends AppRoute {
  const Home();
}

/// A normal main-stack screen opened with `pushForResult<String>`.
final class ColorPicker extends AppRoute {
  const ColorPicker();
}

/// A modal flow, completing with `true` on save and `null` on dismiss.
final class EditProfileFlow extends AppRoute implements KaiselModalRoute<bool> {
  const EditProfileFlow();
}

/// Shared navigation log. Each navigator builds its own observer instance
/// (a NavigatorObserver belongs to one Navigator), but they all append here.
final ValueNotifier<List<String>> _log = ValueNotifier<List<String>>(const []);

class _LogObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name case final name?) _add('→ $name');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name case final name?) _add('← $name');
  }

  // A newly mounted navigator (a flow opening) dispatches its initial
  // observer notifications during build; mutating a listenable bound to
  // widgets there throws markNeedsBuild-during-build. A microtask can't
  // run mid-build, so this defers exactly enough — and from a tap it
  // still lands before the next frame.
  void _add(String entry) =>
      scheduleMicrotask(() => _log.value = [..._log.value, entry]);
}

class _HomeScreen extends StatefulWidget {
  const _HomeScreen();
  @override
  State<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<_HomeScreen> {
  String? _accent;
  String? _profileResult;

  Future<void> _pickAccent() async {
    final picked = await context.pushForResult<String>(const ColorPicker());
    if (!mounted) return;
    setState(() => _accent = picked);
  }

  Future<void> _editProfile() async {
    final saved = await context.router<AppRoute>().run<bool>(
      const EditProfileFlow(),
    );
    if (!mounted) return;
    setState(() {
      _profileResult = switch (saved) {
        true => 'Profile saved',
        _ => 'Edit cancelled',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Results & flows')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: _pickAccent,
              child: const Text('Pick accent colour (pushForResult)'),
            ),
            if (_accent case final accent?) ...[
              const SizedBox(height: 8),
              Text('Accent: $accent'),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _editProfile,
              child: const Text('Edit profile (modal flow)'),
            ),
            if (_profileResult case final result?) ...[
              const SizedBox(height: 8),
              Text(result),
            ],
            const SizedBox(height: 32),
            Text(
              'Navigation log',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Card(
                child: ValueListenableBuilder<List<String>>(
                  valueListenable: _log,
                  builder: (context, entries, _) => ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final entry in entries)
                        Text(
                          entry,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorPickerScreen extends StatelessWidget {
  const _ColorPickerScreen();

  static const _options = ['Teal', 'Amber', 'Violet'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pick a colour')),
      body: ListView(
        children: [
          for (final name in _options)
            ListTile(
              title: Text(name),
              // Return the chosen value to the awaiting pushForResult.
              onTap: () => context.pop(name),
            ),
        ],
      ),
    );
  }
}

class _EditProfileFlowScreen extends StatelessWidget {
  const _EditProfileFlowScreen();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Edit profile',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          // useRootNavigator defaults to true → renders above this flow.
          onPressed: () => showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Help'),
              content: const Text('This dialog renders above the flow.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Got it'),
                ),
              ],
            ),
          ),
          child: const Text('Show help (dialog over the flow)'),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => context.dismissFlow(),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => context.completeFlow<bool>(true),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A transparent flow page that slides its content up from the bottom, and
/// forwards name/arguments so the flow stays observable.
class _SlideUpFlowPage extends Page<Object?> {
  const _SlideUpFlowPage({
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
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => child,
      transitionsBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: child,
      ),
    );
  }
}

Page<Object?> _pageWrapper(KaiselPageWrapperContext<AppRoute> ctx) {
  if (ctx.isFlow) {
    return _SlideUpFlowPage(
      key: ctx.key,
      name: ctx.route.routeName,
      arguments: ctx.route,
      child: ctx.child,
    );
  }
  return MaterialPage<Object?>(
    key: ctx.key,
    name: ctx.route.routeName,
    arguments: ctx.route,
    child: ctx.child,
  );
}

Widget _modalBuilder(
  BuildContext context,
  KaiselModalRoute<Object?> flowRoute,
  Widget flowChild,
) {
  return ColoredBox(
    color: Colors.black.withValues(alpha: 0.6),
    child: Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        decoration: BoxDecoration(
          color: const Color(0xFF14141C),
          borderRadius: BorderRadius.circular(16),
        ),
        child: SafeArea(top: false, child: flowChild),
      ),
    ),
  );
}

final _config = KaiselRouterConfig<AppRoute>(
  initial: const Home(),
  builder: (context, route) => switch (route) {
    Home() => const _HomeScreen(),
    ColorPicker() => const _ColorPickerScreen(),
    EditProfileFlow() => const _EditProfileFlowScreen(),
  },
  pageWrapper: _pageWrapper,
  modalBuilder: _modalBuilder,
  observers: () => [_LogObserver()],
);

void main() {
  runApp(
    MaterialApp.router(
      title: 'kaisel results & flows demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00D4FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        cardColor: const Color(0xFF14141C),
        useMaterial3: true,
      ),
      routerConfig: _config,
    ),
  );
}
