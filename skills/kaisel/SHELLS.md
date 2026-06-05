# Shells

Reference for `KaiselBranchedShell` (multi-branch tab/sidebar layouts)
and `KaiselShell` (single-branch layouts that just wrap content in
chrome). Branched shells are the more common case — start there if
the app has a bottom navigation bar, a sidebar, or any other "this is
the persistent chrome, and the content swaps based on the selected
section" pattern.

## Quick reference

| Type | Purpose |
|:-----|:--------|
| `KaiselBranchedShell` | Widget that hosts N branches; renders the active branch's content inside chrome you supply. |
| `KaiselBranch<R>` | One branch with its own typed router. `KaiselBranch.adaptive(...)` for absorbing layouts. |
| `BranchedShellRouter` | State aggregator for the branches — tracks active branch, exposes a `switchTo` API, notifies on changes. |
| `KaiselBranchedShellChromeBuilder` | `Widget Function(BuildContext, int activeBranch, Widget branchContent, void Function(int) switchBranch)` — builds the chrome around the active branch. |
| `KaiselShell` | Multi-branch shell where **all branches share one route type** `R` (homogeneous). Simpler than `KaiselBranchedShell` when per-branch typing isn't needed. Creates its own `ShellRouter` internally from `branchInitials`. |
| `ShellRouter` | State container for a `KaiselShell` — N branches over a single `R`, plus the active index. Built internally by `KaiselShell`; you don't construct it. |
| `KaiselShellChromeBuilder` | `Widget Function(BuildContext, int activeBranch, Widget branchContent, void Function(int) switchBranch)` — same 4-arg shape as the branched chrome builder. |

## Branched shell — the canonical pattern

```dart
sealed class HomeRoute extends KaiselRoute { const HomeRoute(); }
final class HomeView extends HomeRoute { const HomeView(); }

sealed class ProductRoute extends KaiselRoute { const ProductRoute(); }
final class ProductList extends ProductRoute { const ProductList(); }
final class ProductDetail extends ProductRoute {
  const ProductDetail(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

sealed class SettingsRoute extends KaiselRoute { const SettingsRoute(); }
final class SettingsHome extends SettingsRoute { const SettingsHome(); }

class _AppShellState extends State<AppShell> {
  late final _homeRouter =
      KaiselRouter<HomeRoute>(initial: const HomeView());
  late final _productRouter =
      KaiselRouter<ProductRoute>(initial: const ProductList());
  late final _settingsRouter =
      KaiselRouter<SettingsRoute>(initial: const SettingsHome());

  late final _shell = BranchedShellRouter(
    branches: [_homeRouter, _productRouter, _settingsRouter],
  );

  @override
  void dispose() {
    _shell.dispose();
    _homeRouter.dispose();
    _productRouter.dispose();
    _settingsRouter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KaiselBranchedShell(
      shell: _shell,
      branches: [
        KaiselBranch<HomeRoute>(
          router: _homeRouter,
          pageBuilder: (c, r) => switch (r) {
            HomeView() => const HomeScreen(),
          },
        ),
        KaiselBranch<ProductRoute>(
          router: _productRouter,
          pageBuilder: (c, r) => switch (r) {
            ProductList() => const ProductListScreen(),
            ProductDetail(:final id) => ProductDetailScreen(id: id),
          },
        ),
        KaiselBranch<SettingsRoute>(
          router: _settingsRouter,
          pageBuilder: (c, r) => switch (r) {
            SettingsHome() => const SettingsScreen(),
          },
        ),
      ],
      chromeBuilder: (context, activeBranch, branchContent, switchBranch) {
        return Scaffold(
          body: branchContent,
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: activeBranch,
            onTap: switchBranch,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
              BottomNavigationBarItem(icon: Icon(Icons.shop), label: 'Shop'),
              BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
            ],
          ),
        );
      },
    );
  }
}
```

**Rules:**

- Each branch's router is typed to *that branch's* sealed family
  (`KaiselRouter<HomeRoute>`, not `KaiselRouter<AppRoute>`). This is
  the load-bearing per-branch typing the library is designed around.
- The order of `branches` in `BranchedShellRouter` and in the
  `KaiselBranchedShell.branches` list must match — index 0 in one is
  index 0 in the other.
- Always dispose all routers and the shell aggregator. The shell holds
  listeners; leaking it is a real memory bug, not a theoretical one.

## Per-branch typing as compile-time safety

The branch's typed router rejects routes that don't belong to it:

```dart
// Compiler error — HomeRoute doesn't match ProductRoute's branch:
_homeRouter.push(const ProductDetail('sku-42'));

// Compiler accepts — HomeView is a HomeRoute:
_homeRouter.push(const HomeView());
```

This is the type safety go_router and auto_route can't give you even
with codegen — the codegen approach types the *call*, but the router
itself is still typed to the union. kaisel types the branch router
to its specific sub-union, so the type system rejects accidental
cross-branch pushes at the call site.

## Per-branch state preservation

State preservation across branch switches is the default. Each branch's
router keeps its stack between visits. Visit the products tab, push
two details deep, switch to home, switch back — the products tab is
exactly as you left it, including the two details.

This differs from go_router's `ShellRoute` (which loses tab state) and
matches `StatefulShellRoute.indexedStack`. If you're migrating *from*
a non-stateful shell, the behaviour will be different after the move.
Decide whether you want the new behaviour or whether you need to
explicitly reset stacks on `switchTo`.

If you want to reset a branch on switch, do it in your chrome builder:

```dart
chromeBuilder: (context, activeBranch, branchContent, switchBranch) {
  return Scaffold(
    /* ... */
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: activeBranch,
      onTap: (i) {
        // Reset the target branch's stack before switching.
        if (i == 1) _productRouter.set(const [ProductList()]);
        switchBranch(i);
      },
      /* ... */
    ),
  );
},
```

## Resolving the right router from context

Inside a branch's screens, `context.router<R>()` resolves to that
branch's router. The type parameter matters:

```dart
// Inside a ProductDetailScreen, this is the product branch's router:
context.router<ProductRoute>().pop();

// This would be the *main* router (if accessible), not the branch's:
context.router<AppRoute>().pop();
```

If you need to mutate the top-level state (logout, switch shell route),
use `context.router<AppRoute>()`. If you need to navigate within the
current branch, use the branch's type.

`KaiselBranchedShellContextX` is an extension that adds shell-specific
helpers (e.g., reading the current active branch index from any
descendant of the shell).

## Homogeneous shells (`KaiselShell`)

`KaiselShell<R>` is the simpler sibling of `KaiselBranchedShell`: every
branch shares **one** route type `R`, so there's no per-branch typing.
It builds its own `ShellRouter` internally from `branchInitials` — you
don't construct one, and there's no `shell:` parameter.

**Critical: `R` must be a sealed type scoped to the shell's routes, not
your app-wide `AppRoute`.** The `pageBuilder` switch is exhaustive over
`R`; if `R` is `AppRoute`, the switch has to handle *every* route the app
has, not just the tabs — which is impractical and defeats the point.
Define a dedicated sealed type for the shell, mounted at a marker route:

```dart
// Dedicated sealed type for the shell's branches.
sealed class TabRoute extends KaiselRoute { const TabRoute(); }
final class HomeRoot extends TabRoute { const HomeRoot(); }
final class DiscoverRoot extends TabRoute { const DiscoverRoot(); }
final class ProfileRoot extends TabRoute { const ProfileRoot(); }

KaiselShell<TabRoute>(
  branchInitials: const [HomeRoot(), DiscoverRoot(), ProfileRoot()],
  pageBuilder: (context, route) => switch (route) {
    HomeRoot() => const HomeScreen(),
    DiscoverRoot() => const DiscoverScreen(),
    ProfileRoot() => const ProfileScreen(),
    // exhaustive over TabRoute — add a variant for anything a tab pushes
  },
  chromeBuilder: (context, activeBranch, branchContent, switchBranch) {
    return Scaffold(
      body: branchContent,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: activeBranch,
        onTap: switchBranch,
        items: const [/* ... */],
      ),
    );
  },
)
```

Inside a branch screen, `context.router<TabRoute>()` resolves to the
active branch's router and `context.shellRouter<TabRoute>()` to the
shell aggregator. The trade-off vs. `KaiselBranchedShell`: every branch
shares `TabRoute`, so the compiler can't stop you pushing a "profile"
route into the "home" tab. When tabs need **different** route types (and
that compile-time guard), use `KaiselBranchedShell` with per-branch
sealed types.

## Common mistakes

| Mistake | Fix |
|:--------|:----|
| Branch routers and `branches` list out of sync | The order in `BranchedShellRouter(branches: [...])` and `KaiselBranchedShell(branches: [...])` must match. Mismatch silently shows the wrong content. |
| Typing all branches to `AppRoute` instead of per-branch sealed types | You lose compile-time prevention of cross-branch pushes. The whole point of per-branch typing evaporates. |
| Holding stale router references after the shell disposes | Routers are owned by the shell's State. Don't store references in singletons or service locators that outlive the shell. |
| Calling `switchTo` on the shell router and `set` on a branch router and expecting them to compose into one atomic operation | They're separate mutations. If you need an atomic "switch branch + replace stack" change, do the `set` first, then `switchTo`. |
| Wrapping the whole `KaiselBranchedShell` in a `Scaffold` and also putting a `Scaffold` inside the `chromeBuilder` | Pick one. Nested `Scaffold`s give you two `SafeArea`s, two `AppBar`s, and confused gesture handling. Convention: the chrome builder owns the `Scaffold`. |
