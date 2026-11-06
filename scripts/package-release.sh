#!/bin/zsh
# Builds a release and produces dist/MacIsle-<version>.zip and .dmg for a GitHub release.
# The build is ad-hoc signed (not notarized): users open it the first time with right-click › Open,
# or `xattr -dr com.apple.quarantine /Applications/MacIsle.app`.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Release \
  -derivedDataPath build/dd CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  ENABLE_HARDENED_RUNTIME=NO clean build | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
APP="build/dd/Build/Products/Release/MacIsle.app"
[ -d "$APP" ] || { echo "build failed"; exit 1; }
codesign --force --sign - --timestamp=none "$APP/Contents/Frameworks/MediaRemoteAdapter.framework/Versions/A"
codesign --force --sign - --timestamp=none --preserve-metadata=entitlements "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
mkdir -p dist
rm -f "dist/MacIsle-$VERSION.zip" "dist/MacIsle-$VERSION.dmg"
ditto -c -k --keepParent "$APP" "dist/MacIsle-$VERSION.zip"
STAGE=$(mktemp -d); ditto "$APP" "$STAGE/MacIsle.app"; ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "MacIsle $VERSION" -srcfolder "$STAGE" -ov -format UDZO "dist/MacIsle-$VERSION.dmg"
rm -rf "$STAGE"
shasum -a 256 dist/MacIsle-$VERSION.* 
