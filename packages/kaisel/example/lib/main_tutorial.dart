// The finished app from the docs tutorial (https://kaisel.dev/tutorial/).
//
// Run from the `example/` directory:
//
//   flutter run -t lib/main_tutorial.dart
//
// Routes as a sealed class, exhaustive builder, pushForResult<String> for
// the suggest form, and a guard that gates the members-only trail.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kaisel/kaisel.dart';

sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

final class TrailList extends AppRoute {
  const TrailList();
}

final class TrailDetail extends AppRoute {
  const TrailDetail(this.name);
  final String name;

  @override
  List<Object?> get props => [name];
}

final class SuggestTrail extends AppRoute {
  const SuggestTrail();
}

final class JoinClub extends AppRoute {
  const JoinClub();
}

final _isMember = ValueNotifier<bool>(false);

KaiselGuard<AppRoute> membersGuard(ValueListenable<bool> isMember) {
  return (current, proposed) {
    final gated = proposed.any(
      (r) => r is TrailDetail && r.name == 'Summit Track',
    );
    if (gated && !isMember.value) return const [TrailList(), JoinClub()];
    return proposed;
  };
}

final _config = KaiselRouterConfig<AppRoute>(
  initial: const TrailList(),
  guards: [membersGuard(_isMember)],
  builder: (context, route) => switch (route) {
    TrailList() => const TrailListScreen(),
    TrailDetail(:final name) => TrailDetailScreen(name: name),
    SuggestTrail() => const SuggestTrailScreen(),
    JoinClub() => const JoinClubScreen(),
  },
);

void main() => runApp(MaterialApp.router(routerConfig: _config));

class TrailListScreen extends StatefulWidget {
  const TrailListScreen({super.key});

  @override
  State<TrailListScreen> createState() => _TrailListScreenState();
}

class _TrailListScreenState extends State<TrailListScreen> {
  final _trails = ['Ridge Loop', 'Falls Path', 'Summit Track'];

  Future<void> _suggest() async {
    final name = await context.router<AppRoute>().pushForResult<String>(
      const SuggestTrail(),
    );
    if (name == null || name.isEmpty) return;
    setState(() => _trails.add(name));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trailhead')),
      body: ListView(
        children: [
          for (final name in _trails)
            ListTile(
              title: Text(name),
              onTap: () => context.router<AppRoute>().push(TrailDetail(name)),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _suggest,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class TrailDetailScreen extends StatelessWidget {
  const TrailDetailScreen({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Center(child: Text('Details for $name')),
    );
  }
}

class SuggestTrailScreen extends StatefulWidget {
  const SuggestTrailScreen({super.key});

  @override
  State<SuggestTrailScreen> createState() => _SuggestTrailScreenState();
}

class _SuggestTrailScreenState extends State<SuggestTrailScreen> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Suggest a trail')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: 'Trail name'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.pop(_controller.text),
              child: const Text('Suggest'),
            ),
          ],
        ),
      ),
    );
  }
}

class JoinClubScreen extends StatelessWidget {
  const JoinClubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Members only')),
      body: Center(
        child: FilledButton(
          onPressed: () {
            _isMember.value = true;
            context.router<AppRoute>().set(const [
              TrailList(),
              TrailDetail('Summit Track'),
            ]);
          },
          child: const Text('Join the club'),
        ),
      ),
    );
  }
}
