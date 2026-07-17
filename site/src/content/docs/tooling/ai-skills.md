---
title: AI & editor skills
description: Teach AI coding agents — Claude Code, Cursor, opencode — how kaisel works, so they generate idiomatic kaisel code instead of guessing.
---

kaisel ships an [agent skill](https://github.com/Mastersam07/kaisel/tree/dev/skills/kaisel)
— a set of structured guides that teach AI coding agents (Claude Code, Cursor,
opencode, …) how kaisel works, so they generate idiomatic kaisel code instead
of guessing at the API.

## Install

```sh
npx skills add Mastersam07/kaisel
```

That's it — the [`skills` CLI](https://github.com/vercel-labs/skills) wires
the skill into the agents it detects in your project.

## What the agent learns

The skill covers the same ground as this site's guides — navigation verbs,
shells, modal flows, adaptive layouts, guards, codecs, modules, and
transitions — in a form agents consume before writing code. With it
installed, an agent asked to "add a settings screen" will produce a sealed
route variant, extend your exhaustive `switch`, and navigate with a typed
push instead of inventing string paths.

The skill and this documentation site are generated from the same source
files, so they can't drift apart.
