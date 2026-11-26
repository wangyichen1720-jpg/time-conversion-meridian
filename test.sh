#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
stage="$(mktemp -d "${TMPDIR:-/tmp}/meridian-tests.XXXXXXXX")"
trap 'rm -rf "$stage"' EXIT
core=(Sources/Converter.swift Sources/Zones.swift)
xcrun swiftc -module-cache-path "$stage/modules" "${core[@]}" Tests/ConversionTests.swift -o "$stage/convert"
"$stage/convert"
xcrun swiftc -module-cache-path "$stage/modules" "${core[@]}" Sources/ImageReader.swift Tests/ImageTests.swift -o "$stage/image"
"$stage/image"
