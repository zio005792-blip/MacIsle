#!/bin/zsh
# Build the Dynamic Island edition of Boring Notch and install it to /Applications.
# Usage: scripts/install-local.sh
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Release \
  -derivedDataPath build/dd CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  ENABLE_HARDENED_RUNTIME=NO build | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

APP="build/dd/Build/Products/Release/Boring Notch.app"
[ -d "$APP" ] || { echo "build failed"; exit 1; }

# The bundled MediaRemoteAdapter ships signed by another team; re-sign everything ad-hoc
# so dyld accepts it next to our ad-hoc main binary.
codesign --force --sign - --timestamp=none "$APP/Contents/Frameworks/MediaRemoteAdapter.framework/Versions/A"
codesign --force --sign - --timestamp=none --preserve-metadata=entitlements "$APP"

pkill -9 -f "Boring Notch.app/Contents/MacOS/Boring Notch" || true
pkill -f "mediaremote-adapter.pl" || true
sleep 0.5
rm -rf "/Applications/Boring Notch.app"
ditto "$APP" "/Applications/Boring Notch.app"
open "/Applications/Boring Notch.app"
echo "installed /Applications/Boring Notch.app"
