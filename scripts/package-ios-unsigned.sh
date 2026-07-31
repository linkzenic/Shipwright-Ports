#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT/build-ios-device/soh/Release-iphoneos/Ship of Harkinian.app}"
OUTPUT_PATH="${2:-$ROOT/dist/Ship-of-Harkinian-iOS-unsigned.ipa}"

if [[ "$OUTPUT_PATH" != /* ]]; then
    OUTPUT_PATH="$(pwd)/$OUTPUT_PATH"
fi

if [ ! -d "$APP_PATH" ]; then
    echo "Missing Apple app bundle: $APP_PATH" >&2
    exit 1
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/soh-ios-unsigned.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

mkdir -p "$STAGING_DIR/Payload"
rsync -a \
    --exclude "_CodeSignature" \
    --exclude "embedded.mobileprovision" \
    "$APP_PATH/" "$STAGING_DIR/Payload/Ship of Harkinian.app/"

PUBLIC_APP="$STAGING_DIR/Payload/Ship of Harkinian.app"
codesign --remove-signature "$PUBLIC_APP" 2>/dev/null || true
rm -rf "$PUBLIC_APP/_CodeSignature"
rm -f "$PUBLIC_APP/embedded.mobileprovision"

REQUIRED_BUNDLE_ITEMS=(
    "Ship of Harkinian"
    "Info.plist"
    "soh.o2r"
    "assets/Config_N64_NTSC_10.xml"
    "assets/TexturePool.xml"
    "assets/xml"
)

for item in "${REQUIRED_BUNDLE_ITEMS[@]}"; do
    if [ ! -e "$PUBLIC_APP/$item" ]; then
        echo "Refusing to package an incomplete app bundle: missing $item" >&2
        exit 1
    fi
done

if ! find "$PUBLIC_APP/assets/xml" -type f -print -quit | grep -q .; then
    echo "Refusing to package an incomplete app bundle: assets/xml is empty" >&2
    exit 1
fi

if strings "$PUBLIC_APP/Ship of Harkinian" | grep -q "/Users/"; then
    echo "Refusing to package an executable containing a local user path." >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
(
    cd "$STAGING_DIR"
    /usr/bin/zip -qry "$OUTPUT_PATH" Payload
)

echo "Unsigned IPA: $OUTPUT_PATH"
