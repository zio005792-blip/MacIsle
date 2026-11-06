#!/bin/zsh
# Build MacIsle and install it to /Applications.
# Usage: scripts/install-local.sh
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Release \
  -derivedDataPath build/dd CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  ENABLE_HARDENED_RUNTIME=NO build | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

APP="build/dd/Build/Products/Release/MacIsle.app"
[ -d "$APP" ] || { echo "build failed"; exit 1; }

# The bundled MediaRemoteAdapter ships signed by another team; re-sign ad-hoc so dyld accepts it.
codesign --force --sign - --timestamp=none "$APP/Contents/Frameworks/MediaRemoteAdapter.framework/Versions/A"
codesign --force --sign - --timestamp=none --preserve-metadata=entitlements "$APP"

pkill -9 -f "MacIsle.app/Contents/MacOS/MacIsle" || true
pkill -9 -f "Boring Notch.app/Contents/MacOS/Boring Notch" || true
pkill -f "mediaremote-adapter.pl" || true
sleep 0.5
# Earlier development builds were called "Boring Notch.app": move them to the Trash.
[ -d "/Applications/Boring Notch.app" ] && mv "/Applications/Boring Notch.app" ~/.Trash/"Boring Notch (old MacIsle build) $(date +%s).app"
rm -rf "/Applications/MacIsle.app"
ditto "$APP" "/Applications/MacIsle.app"
open "/Applications/MacIsle.app"
echo "installed /Applications/MacIsle.app"
