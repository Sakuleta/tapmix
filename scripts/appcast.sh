#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)}"
ZIP="dist/Tapmix-$VERSION.zip"
TOOLS=".build/artifacts/sparkle/Sparkle/bin"

if [[ ! -f "$ZIP" ]]; then
    echo "error: $ZIP is missing; run scripts/release.sh first." >&2
    exit 1
fi

if [[ ! -x "$TOOLS/generate_appcast" ]]; then
    echo "error: Sparkle tools are missing; run swift package resolve." >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$ZIP" "$WORK/"

"$TOOLS/generate_appcast" \
    --download-url-prefix "https://github.com/Sakuleta/tapmix/releases/download/v$VERSION/" \
    --link "https://github.com/Sakuleta/tapmix" \
    -o docs/appcast.xml "$WORK"

echo "Updated docs/appcast.xml; commit and push it so GitHub Pages serves the feed."
