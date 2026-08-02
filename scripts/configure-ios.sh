#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:---simulator}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-14.0}"
BUNDLE_ID="${BUNDLE_ID:-com.shipofharkinian.ios}"
SOH_IOS_VERSION="${SOH_IOS_VERSION:-0.1.0}"
SOH_IOS_BUILD_NUMBER="${SOH_IOS_BUILD_NUMBER:-1}"
SOH_ICLOUD_CONTAINER_ID="${SOH_ICLOUD_CONTAINER_ID:-iCloud.com.shipofharkinian.shared}"
SOH_ENABLE_ICLOUD="${SOH_ENABLE_ICLOUD:-ON}"

case "$MODE" in
    --simulator)
        SYSTEM_NAME="iOS"
        IOS_PLATFORM="SIMULATORARM64"
        APPLE_TARGET="ios"
        BUILD_DIR="${IOS_BUILD_DIR:-$ROOT/build-ios-sim}"
        ;;
    --device)
        SYSTEM_NAME="iOS"
        IOS_PLATFORM="OS64"
        APPLE_TARGET="ios"
        BUILD_DIR="${IOS_BUILD_DIR:-$ROOT/build-ios-device}"
        ;;
    --tvos-simulator)
        SYSTEM_NAME="tvOS"
        IOS_PLATFORM="SIMULATORARM64_TVOS"
        APPLE_TARGET="tvos"
        BUILD_DIR="$ROOT/build-tvos-sim"
        BUNDLE_ID="${TVOS_BUNDLE_ID:-com.shipofharkinian.tvos}"
        ;;
    --tvos-device)
        SYSTEM_NAME="tvOS"
        IOS_PLATFORM="TVOS"
        APPLE_TARGET="tvos"
        BUILD_DIR="$ROOT/build-tvos-device"
        BUNDLE_ID="${TVOS_BUNDLE_ID:-com.shipofharkinian.tvos}"
        ;;
    *)
        echo "Usage: scripts/configure-ios.sh [--simulator|--device|--tvos-simulator|--tvos-device]" >&2
        exit 2
        ;;
esac

if [[ ! "$SOH_IOS_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "SOH_IOS_VERSION must use numeric major.minor.patch form." >&2
    exit 2
fi
if [[ ! "$SOH_IOS_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "SOH_IOS_BUILD_NUMBER must be a positive integer." >&2
    exit 2
fi
if [ ! -f "$ROOT/soh/soh.o2r" ]; then
    echo "Missing ROM-free support archive: soh/soh.o2r" >&2
    exit 1
fi

set -- cmake -Wno-unused-cli \
    -S "$ROOT" -B "$BUILD_DIR" \
    -GXcode \
    -DCMAKE_SYSTEM_NAME="$SYSTEM_NAME" \
    -DCMAKE_SYSTEM_VERSION="$DEPLOYMENT_TARGET" \
    -DDEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_BUILD_TYPE:STRING=Release \
    -DENABLE_SCRIPTING=OFF \
    -DBUILD_REMOTE_CONTROL=OFF \
    -DPLATFORM="$IOS_PLATFORM" \
    -DSOH_APPLE_TARGET="$APPLE_TARGET" \
    -DBUNDLE_ID="$BUNDLE_ID" \
    -DSOH_ICLOUD_CONTAINER_ID="$SOH_ICLOUD_CONTAINER_ID" \
    -DSOH_ENABLE_ICLOUD="$SOH_ENABLE_ICLOUD" \
    -DSOH_IOS_VERSION="$SOH_IOS_VERSION" \
    -DSOH_IOS_BUILD_NUMBER="$SOH_IOS_BUILD_NUMBER"

if [ -n "${DEVELOPMENT_TEAM:-}" ]; then
    set -- "$@" \
        "-DCMAKE_XCODE_ATTRIBUTE_DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM" \
        -DSIGN_LIBRARY=ON
fi

"$@"

echo "Configured $BUILD_DIR"
