#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/dist/HP1020 SMB 助手.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/.build/module-cache"
/usr/bin/xcrun swiftc -parse-as-library "$ROOT/Sources/Main.swift" \
    -o "$APP/Contents/MacOS/HP1020Assistant" \
    -target arm64-apple-macos13.0 -module-cache-path "$ROOT/.build/module-cache"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/install.sh" "$ROOT/Resources/uninstall.sh" "$ROOT/Resources/test.pdf" "$APP/Contents/Resources/"
/usr/bin/codesign --force --deep --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/dist/HP1020-SMB-Assistant.zip"
printf 'Built: %s\n' "$APP"
