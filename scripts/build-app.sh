#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Tapmix.app"
IDENTITY="${CODESIGN_IDENTITY:--}"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/Tapmix"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tapmix"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign "$IDENTITY" --identifier com.sakuleta.tapmix "$APP"

echo "Built $APP"
echo "Run with: open $APP"
