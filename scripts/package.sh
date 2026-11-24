#!/bin/sh
# Builds the app for Apple silicon and Intel Macs in one, and wraps it in a disk
# image as dist/maxnines-desktop-<version>.dmg, with a shortcut to Applications to
# drag it to. Needs Xcode.
set -e
cd "$(dirname "$0")/.."
UNIVERSAL=1 scripts/bundle.sh
version=$(cat VERSION)
stage=$(mktemp -d)
cp -R "build/MaxNines Desktop.app" "$stage/"
ln -s /Applications "$stage/Applications"
mkdir -p dist
image="dist/maxnines-desktop-$version.dmg"
rm -f "$image"
hdiutil create -quiet -volname "MaxNines Desktop" -srcfolder "$stage" -format UDZO "$image"
rm -rf "$stage"
echo "Made $image"
