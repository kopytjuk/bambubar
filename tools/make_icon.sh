#!/bin/bash
# Regenerates Resources/AppIcon.icns from the bamboo drawing code.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
swiftc -o "$TMP/icon" tools/icon/main.swift Sources/BambuBar/BambooIcon.swift
"$TMP/icon" "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
rm -rf "$TMP"
echo "Wrote Resources/AppIcon.icns"
