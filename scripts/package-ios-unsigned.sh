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

# A public IPA is intentionally unsigned. A later personal sideload signature
# cannot authorize Linkzenic's private CloudKit container, so prevent the app
# from attempting that unavailable service at runtime.
case "${SOH_PACKAGE_CLOUD:-disabled}" in
    disabled)
        /usr/libexec/PlistBuddy -c 'Set :SOHCloudKitProvisionedBuild false' "$PUBLIC_APP/Info.plist"
        ;;
    provisioned)
        if [ "$(/usr/libexec/PlistBuddy -c 'Print :SOHCloudKitProvisionedBuild' "$PUBLIC_APP/Info.plist")" != "true" ]; then
            echo "Cloud packaging requires a build configured with SOH_ENABLE_ICLOUD=ON." >&2
            exit 1
        fi
        echo "Cloud-enabled unsigned IPA: sign with a profile authorizing the build's configured containers."
        ;;
    *) echo "SOH_PACKAGE_CLOUD must be disabled or provisioned." >&2; exit 1 ;;
esac

REQUIRED_BUNDLE_ITEMS=(
    "Ship of Harkinian"
    "Info.plist"
    "soh.o2r"
    "assets/config.yml"
    "assets/ntsc_1-0"
    "gamecontrollerdb.txt"
)
DEVICE_FAMILY=$(/usr/libexec/PlistBuddy -c 'Print :UIDeviceFamily:0' "$PUBLIC_APP/Info.plist" 2>/dev/null || true)
if [ "$DEVICE_FAMILY" != "3" ]; then
    REQUIRED_BUNDLE_ITEMS+=("fonts/FiraSansCondensed-Bold.ttf" "fonts/MaterialSymbolsRounded-Regular.ttf")
fi

for item in "${REQUIRED_BUNDLE_ITEMS[@]}"; do
    if [ ! -e "$PUBLIC_APP/$item" ]; then
        echo "Refusing to package an incomplete app bundle: missing $item" >&2
        exit 1
    fi
done

if ! find "$PUBLIC_APP/assets/ntsc_1-0" -type f -name '*.yml' -print -quit | grep -q .; then
    echo "Refusing to package an incomplete app bundle: extraction definitions are empty" >&2
    exit 1
fi

if strings "$PUBLIC_APP/Ship of Harkinian" | LC_ALL=C grep -F "/Users/" >/dev/null; then
    echo "Refusing to package an executable containing a local user path." >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
(
    cd "$STAGING_DIR"
    /usr/bin/zip -qry "$OUTPUT_PATH" Payload
)

echo "Unsigned IPA: $OUTPUT_PATH"
