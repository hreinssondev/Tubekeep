#!/bin/sh
# Builds a universal (Apple silicon and Intel), ad-hoc signed Tubekeep.app and packs it into
# dist/Tubekeep-<version>.dmg. Without a Developer ID it can't be notarized; ad-hoc signing
# also means no hardened runtime, which would refuse to load the embedded framework.
set -eu
cd "$(dirname "$0")/.."
version=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

xcodebuild -project Tubekeep.xcodeproj -scheme Tubekeep -configuration Release -derivedDataPath "$work/build" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO \
    -quiet build
app="$work/build/Build/Products/Release/Tubekeep.app"
codesign --verify --deep --strict "$app"

mkdir "$work/dmg"
cp -R "$app" "$work/dmg/"
ln -s /Applications "$work/dmg/Applications"
mkdir -p dist
hdiutil create -volname Tubekeep -srcfolder "$work/dmg" -ov -format UDZO "dist/Tubekeep-$version.dmg" >/dev/null
echo "dist/Tubekeep-$version.dmg"
