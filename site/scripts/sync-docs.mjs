// Syncs the canonical docs into the site's content directory.
//
// The guides in skills/kaisel/ and the migration guides in
// packages/kaisel/doc/migration/ are the single source of truth — they are
// also consumed as editor/AI skills from those paths, so they cannot move.
// This script copies them here at build time, injecting the frontmatter
// Starlight needs. The copies are gitignored; never edit them.
//
// Run: node scripts/sync-docs.mjs   (wired as predev/prebuild)

import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const out = join(repo, 'site', 'src', 'content', 'docs');
const github = 'https://github.com/Mastersam07/kaisel/blob/dev';

const pages = [
  // [source (repo-relative), destination (docs-relative), sidebar slug prefix]
  ...[
    ['NAVIGATION.md', 'navigation'],
    ['SHELLS.md', 'shells'],
    ['MODAL_FLOWS.md', 'modal-flows'],
    ['ADAPTIVE.md', 'adaptive-layouts'],
    ['GUARDS.md', 'guards'],
    ['CODEC.md', 'urls-and-deep-linking'],
    ['MODULES.md', 'modules'],
    ['TRANSITIONS.md', 'transitions'],
  ].map(([file, slug]) => [`skills/kaisel/${file}`, `guides/${slug}.md`]),
  ...[
    ['README.md', 'index'],
    ['from-go-router.md', 'from-go-router'],
    ['from-auto-route.md', 'from-auto-route'],
    ['from-navigator.md', 'from-navigator'],
  ].map(([file, slug]) => [
    `packages/kaisel/doc/migration/${file}`,
    `migration/${slug}.md`,
  ]),
  ['ROADMAP.md', 'roadmap.md'],
  ['packages/kaisel_devtools/README.md', 'tooling/devtools.md', 'DevTools extension'],
  ['packages/kaisel_lint/README.md', 'tooling/lints.md', 'Lints'],
];

// Relative links between synced files become site links; anything else
// repo-relative becomes a GitHub link so it never 404s.
const siteLinks = new Map([
  ['from-go-router.md', '/migration/from-go-router/'],
  ['from-auto-route.md', '/migration/from-auto-route/'],
  ['from-navigator.md', '/migration/from-navigator/'],
]);

rmSync(join(out, 'guides'), { recursive: true, force: true });
rmSync(join(out, 'migration'), { recursive: true, force: true });
rmSync(join(out, 'tooling', 'devtools.md'), { force: true });
rmSync(join(out, 'tooling', 'lints.md'), { force: true });
rmSync(join(out, 'roadmap.md'), { force: true });

const unresolved = [];
for (const [source, destination, titleOverride] of pages) {
  let text = readFileSync(join(repo, source), 'utf8');

  const heading = text.match(/^# (.+)$/m);
  if (!heading) throw new Error(`${source}: no H1 to use as the page title`);
  const title = titleOverride ?? heading[1].trim();
  // Drop everything through the H1 (brand images and badge rows in package
  // READMEs shouldn't render inside a docs page).
  text = text.slice(text.indexOf(heading[0]) + heading[0].length).trimStart();

  text = text.replace(/\]\(([^)\s]+)\)/g, (match, target) => {
    if (/^(https?:|#|mailto:)/.test(target)) return match;
    const [path, anchor = ''] = target.split('#');
    const file = path.split('/').pop();
    if (siteLinks.has(file)) {
      return `](${siteLinks.get(file)}${anchor ? `#${anchor}` : ''})`;
    }
    const sourceDir = source.split('/').slice(0, -1).join('/');
    const resolved = join('/', sourceDir, path).slice(1);
    if (resolved.startsWith('..')) {
      unresolved.push(`${source}: ${target}`);
      return match;
    }
    return `](${github}/${resolved}${anchor ? `#${anchor}` : ''})`;
  });

  const body = [
    '---',
    `title: "${title.replaceAll('"', '\\"')}"`,
    `editUrl: ${github}/${source}`,
    '---',
    '',
    `<!-- Generated from ${source} — edit that file, not this one. -->`,
    '',
    text,
  ].join('\n');

  const destinationPath = join(out, destination);
  mkdirSync(dirname(destinationPath), { recursive: true });
  writeFileSync(destinationPath, body);
  console.log(`synced ${source} -> ${destination}`);
}

if (unresolved.length > 0) {
  console.error('\nLinks escaping the repo root (fix at the source):');
  for (const link of unresolved) console.error(`  ${link}`);
  process.exit(1);
}
