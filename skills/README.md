# kaisel — agent skill

An [agent skill](https://github.com/vercel-labs/skills) that teaches AI coding agents
how the [kaisel](https://pub.dev/packages/kaisel) router works, so they generate
idiomatic kaisel code instead of guessing at the API. It's agent-agnostic — it works
with anything the `skills` CLI supports (Claude Code, Cursor, opencode, and more).

## Install

```sh
npx skills add Mastersam07/kaisel
```

The [`skills` CLI](https://github.com/vercel-labs/skills) copies this directory into
your agent's skills directory (`.claude/skills/`, `.agents/skills/`, etc., depending on
the agent). It's picked up on the next session; the skill triggers when you work with
`package:kaisel` code or mention kaisel's types.

## Contents

- [`kaisel/SKILL.md`](kaisel/SKILL.md) — entry point: the mental model and the key types.
- Topic deep-dives, read on demand:
  [NAVIGATION](kaisel/NAVIGATION.md) ·
  [SHELLS](kaisel/SHELLS.md) ·
  [MODAL_FLOWS](kaisel/MODAL_FLOWS.md) ·
  [MODULES](kaisel/MODULES.md) ·
  [CODEC](kaisel/CODEC.md) ·
  [GUARDS](kaisel/GUARDS.md) ·
  [ADAPTIVE](kaisel/ADAPTIVE.md) ·
  [TRANSITIONS](kaisel/TRANSITIONS.md).
