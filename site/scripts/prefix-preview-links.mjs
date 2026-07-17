// Prefixes SITE_BASE onto root-absolute internal links in the built HTML.
// Preview deploys live under kaisel.dev/pr-N/; links Astro doesn't
// base-prefix (hero actions, content anchors) would otherwise escape the
// preview into production pages. No-op when SITE_BASE is unset.

import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const base = process.env.SITE_BASE;
if (base) {
  const htmlFiles = (dir) =>
    readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) return htmlFiles(path);
      return entry.name.endsWith('.html') ? [path] : [];
    });

  let rewritten = 0;
  for (const file of htmlFiles('dist')) {
    const html = readFileSync(file, 'utf8');
    const fixed = html.replace(
      /href="(\/(?!\/)[^"]*)"/g,
      (match, href) => {
        if (href.startsWith(`${base}/`) || href === base) return match;
        rewritten += 1;
        return `href="${base}${href}"`;
      },
    );
    if (fixed !== html) writeFileSync(file, fixed);
  }
  console.log(`[preview-links] prefixed ${rewritten} links with ${base}`);
}
