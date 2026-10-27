#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

swift test
./scripts/build-app.sh
codesign --verify --strict build/Tapmix.app
test -d build/Tapmix.app/Contents/Frameworks/Sparkle.framework
plutil -extract SUFeedURL raw build/Tapmix.app/Contents/Info.plist > /dev/null
plutil -extract SUPublicEDKey raw build/Tapmix.app/Contents/Info.plist > /dev/null
xmllint --noout docs/appcast.xml

echo "check: OK"
