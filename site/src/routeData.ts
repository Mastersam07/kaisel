import { defineRouteMiddleware } from '@astrojs/starlight/route-data';

// Global announcement banner — the idea behind kaisel. Pages can still
// override with their own `banner` frontmatter.
export const onRequest = defineRouteMiddleware(({ locals }) => {
  const { starlightRoute } = locals;
  starlightRoute.entry.data.banner ??= {
    content:
      'The idea behind kaisel — <a href="https://medium.com/@codefarmer/flutter-routes-as-values-089476ad4d5b">Flutter Routes as Values&nbsp;→</a>',
  };
});
