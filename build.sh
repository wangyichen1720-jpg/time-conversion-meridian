#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
out="${1:-$root/build}"
mkdir -p "$out"
stage="$(mktemp -d "${TMPDIR:-/tmp}/meridian-build.XXXXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Meridian.app"
cache="${MERIDIAN_MODULE_CACHE:-$stage/modules}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
for arch in arm64 x86_64; do
    xcrun swiftc -O -whole-module-optimization -target "$arch-apple-macos13.0" -module-cache-path "$cache" "$root"/Sources/*.swift -o "$stage/Meridian-$arch"
done
xcrun lipo -create "$stage/Meridian-arm64" "$stage/Meridian-x86_64" -output "$app/Contents/MacOS/Meridian"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
xcrun swift -module-cache-path "$cache" "$root/Resources/DrawIcon.swift" "$app/Contents/Resources/Meridian.icns"
codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict "$app"
ditto "$app" "$out/Meridian.app"
echo "Built $out/Meridian.app"
