# kaisel brand assets

`kaisel-icon.svg` is the master — every other file derives from it. The other
`.svg` files embed a copy of the master's `<defs>` block (gradients and the
`mark` group); after editing the master, paste its `<defs>…</defs>` into each
of them, then re-render with `rsvg-convert` (see commands below).

| File | Use |
| --- | --- |
| `kaisel-icon.svg` | Master mark on the dark tile. Source of truth. |
| `kaisel-icon-1024.png` | Hi-res square tile. Downscale for any avatar or icon slot. |
| `kaisel-icon-rounded.svg/png` | App-icon tile with rounded corners. Avatars: X, Discord, Medium, pub.dev publisher. |
| `kaisel-mark.svg/png` | Transparent mark. Package READMEs (core, lint, devtools); anywhere the background should show through. |
| `kaisel-logo-dark.svg/png` | Transparent lockup, white wordmark. README headers on dark backgrounds. |
| `kaisel-logo-light.svg/png` | Transparent lockup, slate wordmark. README headers on light backgrounds. |
| `kaisel-banner.png` | Lockup on the dark tile. dev.to covers, Medium headers, slides — wide slots that want a baked background. |
| `kaisel-social.svg/png` | 1280×640 card with taglines. GitHub social preview, link embeds. |

The `kaisel-icon.webp` copies inside `packages/*/assets/brand/` feed each
pubspec's `screenshots:` field; regenerate them from `kaisel-icon-1024.png`
with `magick kaisel-icon-1024.png -resize 512x512 -quality 90 kaisel-icon.webp`.

Re-render after editing the master:

```sh
rsvg-convert -w 1024 -h 1024 kaisel-icon.svg -o kaisel-icon-1024.png
rsvg-convert -w 512 -h 512 kaisel-icon-rounded.svg -o kaisel-icon-rounded.png
rsvg-convert -w 512 -h 512 kaisel-mark.svg -o kaisel-mark.png
rsvg-convert -w 1600 kaisel-logo-dark.svg -o kaisel-logo-dark.png
rsvg-convert -w 1600 kaisel-logo-light.svg -o kaisel-logo-light.png
rsvg-convert -w 1600 -b '#060A14' kaisel-logo-dark.svg -o kaisel-banner.png
rsvg-convert -w 1280 -h 640 kaisel-social.svg -o kaisel-social.png
```

Colors: background `#060A14`, body teal ramp `#155E75 → #67E8F9`, wing ramp
`#0E7490 → #22D3EE → #A5F3FC`, head ramp `#1D82A6 → #9BEFFC`.
