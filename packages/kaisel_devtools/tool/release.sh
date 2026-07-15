#!/usr/bin/env bash
#
# Release helper for the kaisel DevTools extension.
#
# Three things must move together or the version badge, the package version, and
# the shipped web build silently drift:
#   1. packages/kaisel_devtools/pubspec.yaml          (the source package version)
#   2. packages/kaisel/extension/devtools/config.yaml (the version DevTools shows)
#   3. packages/kaisel/extension/devtools/build/       (the compiled extension)
#
# This bumps (1) and (2) to the same version, then runs build_and_copy for (3).
#
#   packages/kaisel_devtools/tool/release.sh <version>
#   e.g. packages/kaisel_devtools/tool/release.sh 0.3.0
#
# Afterwards: update packages/kaisel_devtools/CHANGELOG.md and commit the
# pubspec and config.yaml. The build/ output stays gitignored; kaisel's
# .pubignore re-includes it at publish time (and keeps the pruned artifacts
# excluded as a backstop).
set -euo pipefail

version="${1:-}"
if [[ -z "$version" ]]; then
  echo "usage: $(basename "$0") <version>   (e.g. 0.3.0)" >&2
  exit 1
fi

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
pubspec="$root/packages/kaisel_devtools/pubspec.yaml"
config="$root/packages/kaisel/extension/devtools/config.yaml"

# Rewrite the first top-level `version:` line in a file, portably.
set_version() {
  local file="$1"
  awk -v v="$version" '
    !done && /^version:/ { print "version: " v; done=1; next }
    { print }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

echo "Setting kaisel_devtools and the extension config to ${version}..."
set_version "$pubspec"
set_version "$config"

echo "Building the DevTools extension…"
# Same flags devtools_extensions' build_and_copy uses, minus
# --no-tree-shake-icons: the extension only uses const icons, so tree-shaking
# is verified safe at compile time and cuts MaterialIcons from 1.6 MB to 9 KB.
( cd "$root/packages/kaisel_devtools" && flutter build web \
    --pwa-strategy=offline-first --release )

echo "Copying into packages/kaisel/extension/devtools/build…"
rm -rf "$root/packages/kaisel/extension/devtools/build"
cp -R "$root/packages/kaisel_devtools/build/web" \
      "$root/packages/kaisel/extension/devtools/build"

# Prune artifacts the extension never loads at runtime: CanvasKit comes from
# Google's CDN (flutter_bootstrap.js), so the local engine variants and debug
# symbols are dead weight (~29 MB), and NOTICES is only fetched by a
# LicensePage the extension doesn't have.
echo "Pruning unused build artifacts…"
rm -rf "$root/packages/kaisel/extension/devtools/build/canvaskit"
rm -f "$root/packages/kaisel/extension/devtools/build/assets/NOTICES"

echo
echo "Done. Remaining manual steps:"
echo "  - add a $version entry to packages/kaisel_devtools/CHANGELOG.md"
echo "  - commit pubspec.yaml and config.yaml (build/ stays gitignored; it"
echo "    ships via kaisel's .pubignore negation when kaisel is published)"
