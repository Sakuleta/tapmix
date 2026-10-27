#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)}"
APP="build/Tapmix.app"
DIST="dist"
IDENTITY="${CODESIGN_IDENTITY:-}"

if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: [^"]*\)"/\1/p' | head -n 1)"
fi

if [[ -z "$IDENTITY" ]]; then
    echo "warning: no Developer ID Application identity; producing a local zip."
    ./scripts/build-app.sh
else
    CODESIGN_IDENTITY="$IDENTITY" ./scripts/build-app.sh
fi

mkdir -p "$DIST"
ZIP="$DIST/Tapmix-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [[ "$IDENTITY" == "Developer ID Application"* ]]; then
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        echo "Notarizing with profile $NOTARY_PROFILE..."
        xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$APP"
        rm -f "$ZIP"
        ditto -c -k --keepParent "$APP" "$ZIP"
    else
        echo "note: set NOTARY_PROFILE to notarize this build."
    fi
fi

echo "Built $ZIP"
shasum -a 256 "$ZIP"

if [[ "$IDENTITY" == "Developer ID Application"* ]]; then
    ./scripts/appcast.sh "$VERSION"
fi
