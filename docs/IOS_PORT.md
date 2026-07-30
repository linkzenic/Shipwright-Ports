# Ship of Harkinian for Apple Platforms

This tree is a direct iOS adaptation of the Android fork. It is not a patch
launcher and does not require a second Ship of Harkinian checkout.

## What is shared with Android

- The Ship of Harkinian game, enhancement, randomizer, and resource code
- libultraship and the Metal renderer
- The SDL input stack and controller mappings
- The ROM-free `soh.o2r` support archive
- The user-data format used by other Ship of Harkinian builds

The Apple layer is intentionally small: CMake/Xcode configuration, application
lifecycle handling, platform-appropriate local storage, CloudKit save sync,
and a native translation of the Android touch overlay on iPhone and iPad.
Touch input appears to the engine as an SDL virtual game
controller, so controller rebinding and gameplay input follow the same path as
Android. The iOS layout preserves the Android controls, behavior, and styling:
left stick, right-side look area, C-direction cross, A/B/X/Y buttons, L/R/Z,
Back/Start, and the visibility toggle.

## Requirements

- macOS with Xcode and the iOS SDK
- The tvOS SDK for Apple TV builds
- CMake
- An arm64 Mac for the simulator configuration
- `soh/soh.o2r`
- A supported Ocarina of Time ROM for first-run extraction

The ROM is never bundled in the app.

The iOS target is universal and supports both iPhone and iPad.

## Simulator build

```sh
scripts/build-ios.sh --simulator
```

The app is written to:

```text
build-ios-sim/soh/Release-iphonesimulator/Ship of Harkinian.app
```

## Device build

For an unsigned compile check:

```sh
scripts/build-ios.sh --device
```

For a signed development build, supply the Apple development-team identifier:

```sh
DEVELOPMENT_TEAM=ABCDE12345 scripts/build-ios.sh --device
```

The default bundle identifier is `com.shipofharkinian.ios`. Override it when
needed:

```sh
BUNDLE_ID=org.example.soh DEVELOPMENT_TEAM=ABCDE12345 \
  scripts/build-ios.sh --device
```

Version and deployment settings can also be overridden:

```sh
SOH_IOS_VERSION=1.2.3 SOH_IOS_BUILD_NUMBER=42 DEPLOYMENT_TARGET=14.0 \
  scripts/build-ios.sh --device
```

## Apple TV builds

For the Apple TV simulator:

```sh
scripts/build-ios.sh --tvos-simulator
```

The app is written to:

```text
build-tvos-sim/soh/Release-appletvsimulator/Ship of Harkinian.app
```

For a signed physical Apple TV build:

```sh
DEVELOPMENT_TEAM=ABCDE12345 scripts/build-ios.sh --tvos-device
```

The default tvOS bundle identifier is `com.shipofharkinian.tvos`. The iOS and
tvOS app identifiers must both be granted access to the same CloudKit container
for cross-device save synchronization.

## Importing a ROM

1. Install and open the app once.
2. In the iOS Files app, open **On My iPhone** or **On My iPad**, then
   **Ship of Harkinian**.
3. Copy a supported ROM into that folder.
4. Return to Ship of Harkinian.

The normal Ship extraction code creates the local game archive in the same
Documents directory. Saves and configuration remain visible through Files for
backup and transfer.

## Importing game data and mods on Apple TV

Apple TV has no Files-app document workflow. The tvOS build therefore starts a
small local transfer server and advertises it with Bonjour:

1. Open Ship of Harkinian on Apple TV.
2. Note the `http://<address>:8080` address shown in the missing-game-data
   prompt or under **Settings > General > Local File Transfer**.
3. On a phone, tablet, or computer connected to the same home network, open
   that address in a browser.
4. Choose **Game Data** for `.o2r`, `.otr`, `.z64`, `.n64`, or `.v64` files, or
   choose **Mods** for mod archives.
5. Return to the game and choose **Rescan**.

Uploads are streamed to a temporary file and atomically moved into the app's
local Documents directory when complete. Game data and mods are not uploaded
to CloudKit. The transfer server can be stopped and restarted from the SOH
settings menu.

## iCloud save synchronization

The iOS settings menu includes an opt-in **Sync Saves with iCloud** setting and
a **Sync Saves Now** action. Save synchronization uses the user's private
CloudKit database in the shared `iCloud.com.shipofharkinian.shared` container.
It does not place files in an iCloud Drive folder.

Only portable game state is synchronized:

- `Save/global.sav`
- `Save/file1.sav`
- `Save/file2.sav`
- `Save/file3.sav`

The large `soh.o2r`, extracted archives, mods, caches, logs, controller
bindings, display settings, and other device-specific configuration remain
local. This avoids large downloads and prevents an iPhone's display or touch
settings from replacing settings appropriate for an iPad, Apple TV, or Mac.

At startup, CloudKit is checked before the save manager loads its metadata. The
newest copy wins based on the source file modification date. If a different
local file is replaced, it is preserved beside the save with an
`.icloud-conflict-<timestamp>` suffix. A newer cloud copy discovered while a
game is running is deferred until the next launch so in-memory game state
cannot immediately overwrite it.

The iCloud container must be enabled for the app identifier and included in
the provisioning profile. It can be overridden when configuring a build:

```sh
SOH_ICLOUD_CONTAINER_ID=iCloud.org.example.soh.shared \
  DEVELOPMENT_TEAM=ABCDE12345 scripts/build-ios.sh --device
```

## Apple-platform storage model

The universal Xcode target supports iPhone and iPad, and a separate tvOS target
uses the same CloudKit save service. CloudKit is deliberately independent of
iCloud Drive because tvOS does not have a general-purpose Files/iCloud Drive
workflow. A future macOS target should use the same CloudKit container and save
record identifiers.

Each platform still needs a local source for the required game data:

- iPhone/iPad: Files document import
- Apple TV: the built-in local-network browser transfer page
- Mac: normal file selection

All targets can then share the four CloudKit save records while keeping game
archives and platform-specific settings local.

## iOS-specific source

- `CMake/ios.cmake` supplies iOS-compatible audio and image dependencies.
- `soh/ios/Info.plist.in` defines the application bundle and Files integration.
- `soh/ios/SOHiCloudSync.mm` synchronizes portable saves through the shared
  private CloudKit container.
- `soh/ios/SOHiOSTouchControls.mm` translates the Android SOH touch layout to
  UIKit while retaining the same SDL controller inputs.
- `soh/ios/SOHTVOSFileServer.mm` provides streamed local-network uploads for
  Apple TV game data and mods.
- `soh/ios/Info-tvOS.plist.in` defines the Apple TV application bundle.
- `scripts/configure-ios.sh` generates iOS or tvOS simulator/device projects.
- `scripts/build-ios.sh` configures and builds the selected target.

## Current validation boundary

The iPad simulator build validates compilation, linking, bundling, startup, and
the universal iOS platform wiring. The tvOS SDK build validates compilation,
linking, platform metadata, controller declarations, and bundle resources. A
tvOS simulator runtime or physical Apple TV is still required to exercise the
browser uploader and CloudKit at runtime. Real-device passes are also required
for code signing,
multi-touch feel, safe-area layout on each target device, suspend/resume,
controller pairing, audio interruptions, and long-session thermal behavior.
