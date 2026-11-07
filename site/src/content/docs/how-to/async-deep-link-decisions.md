---
title: Async deep link decisions
description: Where a deep link lands depends on async state. Keep decode synchronous and put the decision in a guard or a resolver route.
---

Sometimes where a link should land depends on something you have to
await: an entitlement, a feature flag, secure storage, or a server lookup
for a short link. `decode` is synchronous on purpose. It only says what a
URL means. Async decisions go in one of two places, depending on what you
are deciding.

## Deciding whether the user may go there

Entitlements, flags, and stored state are policy, and policy is a guard's
job. Decode the URL to the stack it names, and let an async guard rewrite
it:

```dart
// decode: ['vault'] => const [Home(), Vault()]

KaiselGuard<AppRoute> vaultGuard(Entitlements entitlements) {
  return (current, proposed) async {
    if (proposed.last is! Vault) return proposed;
    if (await entitlements.has(Feature.vault)) return proposed;
    return [...proposed.sublist(0, proposed.length - 1), const Locked()];
  };
}
```

```dart
KaiselRouterConfig<AppRoute>(
  guards: [vaultGuard(entitlements)],
  reevaluateOn: entitlements, // any Listenable
  ...
)
```

The same guard covers links, `push`, and `set`, so the rule lives in one
place. With `reevaluateOn`, it also runs again when the entitlement
changes: a user sitting on `Vault` when access lapses is moved to
`Locked`. Granting access later doesn't send them back to `Vault`
on its own. Give the `Locked` screen a way back in, such as a button that
pushes `Vault` again.

## Working out where a link points

Some links are opaque: `/s/abc123` means nothing until a server resolves
it. Decode those to a resolver route, and let its screen do the lookup:

```dart
// decode: ['s', final code] => [const Home(), ResolveLink(code)]

class _ResolveLinkScreenState extends State<ResolveLinkScreen> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    setState(() => _error = null);
    try {
      final id = await api.resolveShortLink(widget.code);
      if (!mounted) return;
      await context.router<AppRoute>().replaceTop(Product(id));
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: _error == null
          ? const CircularProgressIndicator()
          : TextButton(onPressed: _resolve, child: const Text('Retry')),
    ),
  );
}
```

`replaceTop` swaps the resolver for the real screen, so back goes to
`Home`, not to a spinner.

## Why not an async decode

- A decode only runs when a link arrives. A guard also runs on in-app
  navigation and, with `reevaluateOn`, when the state changes.
- While a decode is awaited there is no screen to show progress or an
  error. A guard can redirect to one, and a resolver route is one.
- kaisel also calls `decode` synchronously outside the parser (for example
  to check that a URL round trips), and an async result can't be used
  there.

See the [guards reference](/guides/guards/) and
[URLs & deep linking](/guides/urls-and-deep-linking/) for the details.
