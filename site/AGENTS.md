# kaisel docs site

## Development

Always use the npm scripts, never `astro` directly — the `predev`/`prebuild`
hooks run `scripts/sync-docs.mjs`, which pulls the canonical docs
(`skills/kaisel/`, `packages/kaisel/doc/migration/`, `ROADMAP.md`) into
`src/content/docs/`. Running Astro directly serves stale or missing content.

```sh
npm run dev      # sync + dev server at localhost:4321
npm run build    # sync + production build + Pagefind search index
npm run preview  # serve dist/ (search only works here, not in dev)
npm run sync     # re-sync after editing canonical docs while dev is running
```

Never edit `src/content/docs/guides/`, `src/content/docs/migration/`, or
`src/content/docs/roadmap.md` — they are gitignored, generated copies. Edit
the canonical files instead.

`npx astro check` / `npx astro add` are fine to call directly — they don't
serve or build content.

## Docs feedback triage

Reader feedback (docs-feedback issues, tweets, Discord questions) maps to
exactly one home — pick it by the *kind* of confusion:

- **Arrived with other-router vocabulary** ("nested routing", "declarative")
  → add a row to the Coming-from-another-router table in `concepts.md`,
  and work the phrase into the relevant reference guide's opening so
  search finds it.
- **Couldn't accomplish a task** → a new how-to page
  (`src/content/docs/how-to/`) — recipe only, link to reference for depth.
- **Task exists but page was too dense / assumed too much** → the tutorial
  or the guide's problem-first opening, not a new page.
- **API detail missing or wrong** → the canonical reference guide in
  `skills/kaisel/` (it syncs here and to the AI skill).

Monthly: check the Umami dashboard (cloud.umami.is) — the Pages view
groups naturally by URL prefix (`/how-to/`, `/guides/`, `/tutorial/`,
`/concepts/`, `/migration/`), which answers "which docs layer gets read".
That plus the open `documentation` issues picks what to write next.
Don't write docs nobody asked for.

## Documentation

Astro/Starlight docs: https://docs.astro.build and
https://starlight.astro.build
