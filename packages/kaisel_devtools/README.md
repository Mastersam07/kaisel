# kaisel_devtools

The DevTools extension for [`kaisel`](../kaisel) — a live inspector for your
app's navigation state.

It reads the snapshot that `KaiselInspector` (in `kaisel` / `kaisel_core`)
publishes over the VM service in debug builds, and renders it inside DevTools.
There is **no integration step**: any app that depends on `kaisel` and runs in
debug mode exposes the data automatically; just open DevTools and select the
**kaisel** tab.

## What it shows

- **Stack** — the main router's live stack (entry id, route type, props,
  label), top-of-stack first, with newly-pushed entries highlighted (a diff
  against the previous state).
- **Shells / Modules / Flows** — branched shells (active branch + each branch's
  stack), mounted modules, and active modal flows, each as its own panel.
- **Guards** — the last guard-pipeline run: the proposed stack in, each guard's
  effect (changed / no-op), and the final stack out. Answers "why was my
  navigation rewritten?"
- **Problems** — flags no-op mutations (the missing-`props` bug) and broken
  codec round-trips.
- **Log** — a transitions log that infers each navigation (push / pop /
  switchBranch / …) from consecutive snapshots, and shows the **app call site
  behind it** — click a frame to open it in your editor when DevTools is
  embedded in an IDE.
- **URL** — the URL the current configuration encodes to (when a codec is
  wired), with a deep-link **decode** preview, and whether the last navigation
  was reported to browser history as a **push** or a **replace**.
- **History** — the main router's past stacks, with time-travel (under the
  Write toggle).

A **Write** toggle (off by default) turns the inspector into a driver: pop,
switch a branch, dismiss a flow, apply a deep link, or time-travel.

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

**Releasing.** Three things must move together — this package's `version`, the
`version` in `config.yaml` (the badge DevTools shows), and the rebuilt `build/`
output — or they drift. `tool/release.sh` does all three:

```sh
packages/kaisel_devtools/tool/release.sh 0.3.0
```

Then add a CHANGELOG entry and commit the two version files.

## Verifying locally

1. Build the extension (command above).
2. Run a kaisel app in debug, e.g. `cd packages/kaisel/example && flutter run`.
3. Open DevTools for that session and select the **kaisel** tab.
4. Navigate in the app — the Stack panel updates live.
