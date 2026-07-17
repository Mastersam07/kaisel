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

## Documentation

Astro/Starlight docs: https://docs.astro.build and
https://starlight.astro.build
