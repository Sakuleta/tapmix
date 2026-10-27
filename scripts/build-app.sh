#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Tapmix.app"
DEFAULT_IDENTITY="Tapmix Dev"
APPLE_DEVELOPMENT="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: [^"]*\)"/\1/p' | head -n 1)"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    IDENTITY="$CODESIGN_IDENTITY"
elif security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$DEFAULT_IDENTITY"; then
    IDENTITY="$DEFAULT_IDENTITY"
elif [[ -n "$APPLE_DEVELOPMENT" ]]; then
    IDENTITY="$APPLE_DEVELOPMENT"
else
    IDENTITY="-"
    echo "warning: using ad-hoc signing; macOS may ask for audio permission after each rebuild."
    echo "         Create a 'Tapmix Dev' code-signing certificate (see README) or set CODESIGN_IDENTITY."
fi

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/Tapmix"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tapmix"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "$IDENTITY" --identifier com.mardinli.tapmix "$APP"

echo "Built $APP (signed with: $IDENTITY)"
echo "Run with: open $APP"
