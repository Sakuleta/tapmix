#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

swift test
./scripts/build-app.sh
codesign --verify --strict build/Tapmix.app

echo "check: OK"
