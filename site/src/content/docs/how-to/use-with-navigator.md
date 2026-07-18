---
title: Use dialogs, sheets, and PopScope
description: kaisel is Flutter's Navigator under the hood — showDialog, bottom sheets, PopScope, and the AppBar back button all work as normal.
---

You want the ordinary Navigator things — `showDialog`, bottom sheets,
`PopScope`, the AppBar back arrow — and you've heard routers can fight
them.

kaisel can't fight the Navigator, because kaisel **is** the Navigator:
the router drives Flutter's official Pages API, and every kaisel screen
is a real route on a real `Navigator`. The ordinary things work
unchanged.

## Dialogs and sheets

```dart
final confirmed = await showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Delete trail?'),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('Delete'),
      ),
    ],
  ),
);
```

Exactly as in any Flutter app — including `Navigator.of(context).pop()`
to close it. Dialogs and sheets are *pageless* routes that layer on top
of kaisel's page-based ones; system back closes them first, then starts
popping kaisel routes. They even render correctly above
[modal flows](/guides/modal-flows/).

Use raw Navigator for **ephemeral UI** (dialogs, sheets, menus) and
kaisel routes for **screens** — the same division of labor as any
Router-API app. What to avoid is managing the same screen both ways.

## Blocking back — PopScope

`WillPopScope` was deprecated by Flutter itself (predictive back needs
ahead-of-time answers, not just-in-time vetoes). Its replacement,
`PopScope`, works on kaisel screens like on any route:

```dart
PopScope(
  canPop: !hasUnsavedChanges,
  onPopInvokedWithResult: (didPop, result) async {
    if (didPop) return;
    final leave = await showDialog<bool>(/* "Discard changes?" */);
    if (leave == true && context.mounted) context.pop();
  },
  child: ...,
)
```

`canPop: false` blocks the system back gesture and the AppBar arrow;
the callback runs so you can ask and then pop programmatically.

kaisel adds a second, router-level layer: a [guard](/guides/guards/) can
veto or transform any *programmatic* stack change — including `pop()` —
as a pure, unit-testable function. Rule of thumb: **PopScope for system
back** (the gesture has already been promised to the OS), **guards for
everything that goes through the router**.

## The AppBar back arrow

Appears and works with zero configuration. `AppBar` shows its inferred
back button whenever the current route can pop — and since kaisel pages
are ordinary `ModalRoute`s, `AppBar` can't tell kaisel is involved at
all. Inside [shells](/guides/shells/), system back pops the active tab's
own stack first, then falls through — also automatic.
