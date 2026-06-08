# kaisel_devtools

The DevTools extension for [`kaisel`](../kaisel) — a live inspector for your
app's navigation state.

It reads the snapshot that `KaiselInspector` (in `kaisel` / `kaisel_core`)
publishes over the VM service in debug builds, and renders it inside DevTools.
There is **no integration step**: any app that depends on `kaisel` and runs in
debug mode exposes the data automatically; just open DevTools and select the
**kaisel** tab.

## What it shows (v1)

- **Stack** — the main router's live stack (entry id, route type, props,
  label), top-of-stack first, with newly-pushed entries highlighted (a diff
  against the previous state).
- **Guards** — the last guard-pipeline run: the proposed stack in, each guard's
  effect (changed / no-op), and the final stack out. Answers "why was my
  navigation rewritten?"
- **URL** — the URL the current configuration encodes to (when a codec is
  wired).

A header line summarises shells / modules / active flows; dedicated panels for
those land in a later checkpoint.

## How it connects

This package is a Flutter **web app**. Its built output is copied into
`packages/kaisel/extension/devtools/build/`, where DevTools discovers it via
`packages/kaisel/extension/devtools/config.yaml`. The build output is generated,
not committed — rebuild it after changing the UI with:

```sh
# from the repo root
dart run devtools_extensions build_and_copy \
  --source=packages/kaisel_devtools \
  --dest=packages/kaisel/extension/devtools
```

## Verifying locally

1. Build the extension (command above).
2. Run a kaisel app in debug, e.g. `cd packages/kaisel/example && flutter run`.
3. Open DevTools for that session and select the **kaisel** tab.
4. Navigate in the app — the Stack panel updates live.
