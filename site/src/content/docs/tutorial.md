---
title: 'Tutorial: your first kaisel app'
description: Build a small app end to end — routes, navigation, a typed result, and a guard — in about twenty minutes.
---

You'll build **Trailhead**, a tiny hiking-trails app, from `flutter create`
to a working guard. Four steps, each pasteable and runnable; along the way
every core kaisel idea shows up once. Twenty minutes, no prior kaisel
knowledge assumed — though the [mental model](/concepts/) makes everything
here click faster.

If you get stuck at any step, the finished app ships as a runnable
example — compare against
[`main_tutorial.dart`](https://github.com/Mastersam07/kaisel/blob/dev/packages/kaisel/example/lib/main_tutorial.dart).

## Step 0 — Set up

```sh
flutter create trailhead
cd trailhead
flutter pub add kaisel
```

Replace `lib/main.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:kaisel/kaisel.dart';

sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

final class TrailList extends AppRoute {
  const TrailList();
}

final _config = KaiselRouterConfig<AppRoute>(
  initial: const TrailList(),
  builder: (context, route) => switch (route) {
    TrailList() => const TrailListScreen(),
  },
);

void main() => runApp(MaterialApp.router(routerConfig: _config));

class TrailListScreen extends StatelessWidget {
  const TrailListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trailhead')),
      body: const Center(child: Text('No trails yet')),
    );
  }
}
```

`flutter run` — one screen. Notice what's *not* there: no route table, no
path strings, no delegate wiring. A sealed class with one variant, a
builder that turns it into a screen, done.

## Step 1 — A second screen, and the compiler earns its keep

Add a route *with data* — a detail screen for one trail. Add the variant:

```dart
final class TrailDetail extends AppRoute {
  const TrailDetail(this.name);
  final String name;

  @override
  List<Object?> get props => [name];
}
```

Save, and **your app no longer compiles**. That's the feature: the
`switch` in the builder is exhaustive over `AppRoute`, and it doesn't
handle `TrailDetail` yet. In a string-routed app this mistake surfaces at
runtime as an unknown-route error; here it can't survive compilation. Fix
it by handling the new case:

```dart
builder: (context, route) => switch (route) {
  TrailList() => const TrailListScreen(),
  TrailDetail(:final name) => TrailDetailScreen(name: name),
},
```

Now give the list something to tap, and navigate with a value — the route
object *is* the argument:

```dart
class TrailListScreen extends StatelessWidget {
  const TrailListScreen({super.key});

  static const _trails = ['Ridge Loop', 'Falls Path', 'Summit Track'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trailhead')),
      body: ListView(
        children: [
          for (final name in _trails)
            ListTile(
              title: Text(name),
              onTap: () =>
                  context.router<AppRoute>().push(TrailDetail(name)),
            ),
        ],
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
```

Run it. Tap a trail — it pushes. The AppBar back arrow and system back
both pop, with no code from you: the stack went from `[TrailList()]` to
`[TrailList(), TrailDetail('Ridge Loop')]` and back. The stack is a value
the router owns; push and pop are list operations on it.

## Step 2 — A screen that returns a value

Users should be able to suggest a trail. That's a form screen that hands
a result back to its caller — no callbacks, no shared mutable state, just
a typed `Future`. Add the route and screen:

```dart
final class SuggestTrail extends AppRoute {
  const SuggestTrail();
}
```

```dart
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
```

The compiler will walk you to the builder again — add
`SuggestTrail() => const SuggestTrailScreen(),` to the switch.

Now open it from the list with `pushForResult<T>` and await the answer.
Make `TrailListScreen` stateful (its trail list is about to grow), and
add a FloatingActionButton:

```dart
class _TrailListScreenState extends State<TrailListScreen> {
  final _trails = ['Ridge Loop', 'Falls Path', 'Summit Track'];

  Future<void> _suggest() async {
    final name = await context.router<AppRoute>()
        .pushForResult<String>(const SuggestTrail());
    if (name == null || name.isEmpty) return;
    setState(() => _trails.add(name));
  }

  // in build's Scaffold:
  // floatingActionButton:
  //     FloatingActionButton(onPressed: _suggest, child: const Icon(Icons.add)),
}
```

Run it. Suggest a trail, and it appears in the list. Dismiss the screen
with back instead, and the future resolves with `null` — dismissal is a
first-class outcome you handle in one place, not an error.

## Step 3 — A guard

The Summit Track is members-only. In kaisel a guard is a pure function
over *proposed stacks*: it sees where the app wants to go and returns
where it's allowed to go. Add a members flag, a Join screen, and the
guard:

```dart
import 'package:flutter/foundation.dart'; // ValueListenable

final _isMember = ValueNotifier<bool>(false);

final class JoinClub extends AppRoute {
  const JoinClub();
}

KaiselGuard<AppRoute> membersGuard(ValueListenable<bool> isMember) {
  return (current, proposed) {
    final gated = proposed
        .any((r) => r is TrailDetail && r.name == 'Summit Track');
    if (gated && !isMember.value) return const [TrailList(), JoinClub()];
    return proposed;
  };
}
```

Register it on the config, and handle the new route in the builder:

```dart
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
```

```dart
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
            context.router<AppRoute>().set(
              const [TrailList(), TrailDetail('Summit Track')],
            );
          },
          child: const Text('Join the club'),
        ),
      ),
    );
  }
}
```

Run it. Tap **Summit Track**: instead of the detail, the Join screen
appears — the guard rewrote the proposed stack before it was applied.
Join, and `set` replaces the whole stack with the destination in one
atomic move. Notice what the guard is: not middleware with a context, not
a callback on a route — a function from lists to lists. You could unit
test it with no widgets:

```dart
test('summit track is gated', () {
  final guard = membersGuard(ValueNotifier(false));
  expect(
    guard(const [TrailList()], const [TrailList(), TrailDetail('Summit Track')]),
    const [TrailList(), JoinClub()],
  );
});
```

## What you just used

In ~150 lines you touched every core idea:

- **Routes as values** — a sealed class; parameters are fields
- **Exhaustive builds** — the compiler found every unhandled screen
- **The stack as state** — push/pop/set as list operations
- **Typed results** — `pushForResult<T>` and `pop(value)`
- **Guards** — pure, testable functions over proposed stacks

## Where next

- [The mental model](/concepts/) — why it all fits together.
- [Shells & tabs](/guides/shells/) — give Trailhead a bottom nav where
  each tab keeps its own history.
- [URLs & deep linking](/guides/urls-and-deep-linking/) — make
  `/trail/ridge-loop` open the right screen on the web.
- The finished Trailhead app ships as a runnable example:
  [`main_tutorial.dart`](https://github.com/Mastersam07/kaisel/blob/dev/packages/kaisel/example/lib/main_tutorial.dart)
  — compare against your result.
- The [example gallery](https://github.com/Mastersam07/kaisel/tree/dev/packages/kaisel/example)
  — sixteen runnable apps, one per feature.
