#!/bin/sh
# Rebuilds Vendor/MediaRemoteAdapter.framework from https://github.com/ungive/mediaremote-adapter
# as a universal (Intel and Apple silicon) framework that runs on macOS 13 and later.
set -eu
vendor="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git clone -q --depth 1 https://github.com/ungive/mediaremote-adapter.git "$work/src"
cd "$work/src"
sources=$(sed -n '/set(ADAPTER_SOURCES/,/)/p' CMakeLists.txt | grep -o 'src/[^ )]*\.m')
fw="$work/MediaRemoteAdapter.framework"
mkdir -p "$fw/Versions/A/Resources"
clang -dynamiclib -arch x86_64 -arch arm64 -mmacosx-version-min=13.0 -O2 -fobjc-arc -fvisibility=default \
    -Iinclude -Isrc $sources -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
    -o "$fw/Versions/A/MediaRemoteAdapter"
cp "$vendor/MediaRemoteAdapter.framework/Versions/A/Resources/Info.plist" "$fw/Versions/A/Resources/"
ln -s A "$fw/Versions/Current"
ln -s Versions/Current/MediaRemoteAdapter "$fw/MediaRemoteAdapter"
ln -s Versions/Current/Resources "$fw/Resources"
codesign --force --sign - "$fw"
install -m 755 bin/mediaremote-adapter.pl "$vendor/mediaremote-adapter.pl"
rm -rf "$vendor/MediaRemoteAdapter.framework"
mv "$fw" "$vendor/"
