// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://kaisel.dev',
  integrations: [
    starlight({
      title: 'kaisel',
      description:
        'A Dart 3-native router for Flutter — sealed routes, pattern matching, and a stack-as-value model. No string paths, no codegen.',
      logo: { src: './src/assets/kaisel-mark.svg', alt: 'kaisel' },
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
      customCss: ['./src/styles/custom.css'],
      head: [
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
        { label: 'Start here', items: ['getting-started'] },
        {
          label: 'Guides',
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
            { label: 'From go_router', slug: 'migration/from-go-router' },
            { label: 'From auto_route', slug: 'migration/from-auto-route' },
            { label: 'From Navigator', slug: 'migration/from-navigator' },
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
