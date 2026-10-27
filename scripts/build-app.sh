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

SPARKLE_FRAMEWORK="$(find .build/artifacts -path '*Sparkle.xcframework/*/Sparkle.framework' -type d 2>/dev/null | head -n 1)"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
    echo "error: Sparkle.framework is missing; run swift package resolve." >&2
    exit 1
fi
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Tapmix" 2>/dev/null || true

SIGN=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" == "Developer ID Application"* ]]; then
    SIGN+=(--options runtime --timestamp)
fi

# Inside-out: Sparkle's helpers, then the framework, then the app.
SPARKLE_DIR="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for item in "$SPARKLE_DIR/Autoupdate" "$SPARKLE_DIR/Autoupdate.app" "$SPARKLE_DIR/Updater.app" "$SPARKLE_DIR/XPCServices/"*.xpc; do
    [[ -e "$item" ]] && codesign "${SIGN[@]}" "$item"
done
codesign "${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN[@]}" --identifier com.mardinli.tapmix "$APP"

echo "Built $APP (signed with: $IDENTITY)"
echo "Run with: open $APP"
