#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${SOH_TOUCH_CHECK_DIR:-/private/tmp/soh-ios-touch-checks}"
APP="$OUT/SOH Touch UI Checks.app"
mkdir -p "$APP/fonts"
cp "$ROOT/tests/ios_touch_hud/Info.plist" "$APP/Info.plist"
cp "$ROOT/Android/app/src/main/assets/fonts/"* "$APP/fonts/"
xcrun --sdk iphonesimulator clang++ -std=c++20 -fobjc-arc -target arm64-apple-ios15.0-simulator \
    -I "$ROOT/soh" "$ROOT/tests/ios_touch_hud/main.mm" -framework UIKit -framework Foundation -framework CoreText \
    -framework QuartzCore -framework CoreGraphics \
    -o "$APP/TouchChecks"
codesign --force --sign - "$APP"
echo "$APP"
