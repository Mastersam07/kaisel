// @ts-check
import { readFileSync } from 'node:fs';
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightLinksValidator from 'starlight-links-validator';

// Set by the docs workflow for PR preview deploys (e.g. /pr-42). Previews
// live under a subpath of the production origin and must not be indexed.
const previewBase = process.env.SITE_BASE;

// Set only by the production deploy job — local dev, validation builds, and
// PR previews ship no analytics.
const withAnalytics = Boolean(process.env.DOCS_ANALYTICS);

const kaiselVersion = readFileSync(
  new URL('../packages/kaisel/pubspec.yaml', import.meta.url),
  'utf8',
).match(/^version:\s*(\S+)/m)[1];

export default defineConfig({
  site: 'https://kaisel.dev',
  base: previewBase ?? '/',
  integrations: [
    starlight({
      routeMiddleware: './src/routeData.ts',
      plugins: previewBase ? [] : [starlightLinksValidator()],
      title: 'kaisel',
      description:
        'A Dart 3-native router for Flutter — sealed routes, pattern matching, and a stack-as-value model. No string paths, no codegen.',
      logo: {
        dark: './src/assets/kaisel-mark.svg',
        light: './src/assets/kaisel-mark-light.svg',
        alt: 'kaisel',
      },
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/Mastersam07/kaisel',
        },
        {
          icon: 'seti:dart',
          label: 'pub.dev',
          href: 'https://pub.dev/packages/kaisel',
        },
      ],
      editLink: {
        baseUrl:
          'https://github.com/Mastersam07/kaisel/edit/dev/site/src/content/docs/',
      },
      customCss: ['./src/styles/custom.css'],
      head: [
        ...(previewBase
          ? [
              {
                tag: 'meta',
                attrs: { name: 'robots', content: 'noindex, nofollow' },
              },
            ]
          : []),
        ...(withAnalytics
          ? [
              {
                tag: 'script',
                attrs: {
                  defer: true,
                  src: 'https://cloud.umami.is/script.js',
                  'data-website-id': '59e77c80-d5c4-45a9-8aa5-c47097dd2376',
                },
              },
            ]
          : []),
        {
          tag: 'style',
          content: `:root { --kaisel-version: 'v${kaiselVersion}'; }`,
        },
        {
          tag: 'meta',
          attrs: { property: 'og:image', content: 'https://kaisel.dev/og.png' },
        },
        {
          tag: 'meta',
          attrs: { name: 'twitter:card', content: 'summary_large_image' },
        },
        {
          tag: 'meta',
          attrs: { name: 'twitter:image', content: 'https://kaisel.dev/og.png' },
        },
      ],
      sidebar: [
        {
          label: 'Start here',
          items: [
            'getting-started',
            { label: 'Tutorial: your first app', slug: 'tutorial' },
            { label: 'The mental model', slug: 'concepts' },
          ],
        },
        {
          label: 'How-to',
          items: [
            { label: 'Return a value from a screen', slug: 'how-to/return-a-value' },
            { label: 'Redirect to login', slug: 'how-to/redirect-to-login' },
            { label: 'Drive the stack from app state', slug: 'how-to/state-driven-stack' },
            { label: 'Deep link into a screen', slug: 'how-to/deep-link' },
            { label: 'Track screens in analytics', slug: 'how-to/track-screens' },
            { label: 'Use dialogs, sheets, and PopScope', slug: 'how-to/use-with-navigator' },
          ],
        },
        {
          label: 'Reference',
          items: [
            { label: 'Navigation', slug: 'guides/navigation' },
            { label: 'Shells & tabs', slug: 'guides/shells' },
            { label: 'Modal flows', slug: 'guides/modal-flows' },
            { label: 'Adaptive layouts', slug: 'guides/adaptive-layouts' },
            { label: 'Guards', slug: 'guides/guards' },
            { label: 'URLs & deep linking', slug: 'guides/urls-and-deep-linking' },
            { label: 'Modules', slug: 'guides/modules' },
            { label: 'Transitions', slug: 'guides/transitions' },
          ],
        },
        {
          label: 'Migration',
          items: [
            { label: 'Overview', slug: 'migration' },
            { label: 'From go_router', slug: 'migration/from-go-router' },
            { label: 'From auto_route', slug: 'migration/from-auto-route' },
            { label: 'From Navigator', slug: 'migration/from-navigator' },
          ],
        },
        {
          label: 'Tooling',
          items: [
            { label: 'DevTools extension', slug: 'tooling/devtools' },
            { label: 'Lints', slug: 'tooling/lints' },
            { label: 'AI & editor skills', slug: 'tooling/ai-skills' },
          ],
        },
        {
          label: 'Project',
          items: [
            { label: 'Roadmap', slug: 'roadmap' },
            {
              label: 'API reference',
              link: 'https://pub.dev/documentation/kaisel/latest/',
              attrs: { target: '_blank' },
            },
            {
              label: 'Examples',
              link: 'https://github.com/Mastersam07/kaisel/tree/dev/packages/kaisel/example',
              attrs: { target: '_blank' },
            },
          ],
        },
      ],
    }),
  ],
});
