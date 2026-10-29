# Ship of Harkinian — Android, iOS, and tvOS

Linkzenic's Android, iOS, and Apple TV ports of [Harbour Masters' Ship of Harkinian](https://github.com/HarbourMasters/Shipwright), together in one repository.

**This repository now focuses on standard Ship of Harkinian.** NEI, Cel Shading, and Fusion are not included in the unified release.

The repository was renamed from `Shipwright-Android` to `Shipwright-Ports`. Existing GitHub links redirect here.

## Downloads and release status

Download published builds from [Releases](https://github.com/linkzenic/Shipwright-Ports/releases). Read the notes for the release you install; the latest published release may not yet include every platform.

No game ROMs or extracted game assets are included. You must supply a supported, legally obtained Ocarina of Time ROM. Check compatibility with [the ROM checker](https://ship.equipment/) or [supported hashes](docs/supportedHashes.json).

## Android

- Customizable Classic, N64, GameCube, and Modern touch layouts.
- A layout editor with movable, resizable, and individually hideable controls.
- Independent touch assignments, manual-jump options, extra item buttons, modifier assignments, and floating-stick controls.
- Item icons, contextual actions, Fairy, and Map controls integrated into the touch layouts.

### Installation and updates

1. Download the standard Android APK from Releases.
2. Install it over your existing Linkzenic standard SOH app to retain its app data. Do not uninstall first.
3. On first setup, choose the user-data folder and allow the app to prepare its support files.
4. Select your supported ROM when prompted to extract game data.

Android requires Android 7 or later and compatible OpenGL ES 3.0 hardware. Standard SOH uses the selected `SOH` user-data folder; check Settings > General for the active location.

Use the Android back gesture/button or the mapped controller menu button to open settings. Physical-controller mappings are under Settings > Controls; touch options are under Settings > Touch Controls.

## iOS

- Customizable Classic, N64, GameCube, and Modern touch layouts.
- A layout editor with movable, resizable, and individually hideable controls.
- Independent touch assignments, manual-jump options, extra item buttons, modifier assignments, and floating-stick controls.
- Item icons, contextual actions, Fairy, and Map controls integrated into the touch layouts.
- Automatic SOH user-folder syncing to iCloud Drive on properly provisioned builds, including saves, mods, and settings.
- CloudKit save syncing with tvOS, with conflicting saves preserved for review.

### Installation and files

Apple downloads are unsigned IPAs unless a release explicitly says otherwise. Sign and install them using a compatible signing method. Keep the same app identifier and signing setup when updating; do not delete the existing app if you want to retain its local data.

Use the app's file-import options to add compatible game data generated from your own supported ROM. Local files remain available offline. On correctly provisioned builds, the app automatically creates the visible **SOH** folder in iCloud Drive. A folder-picker fallback is available when native iCloud Documents access is unavailable.

Sync checks run while the app is active and at launch/foreground. External settings and resource changes apply after restarting. Deletions do not automatically propagate. Runtime logs, caches, temporary files, and sync bookkeeping are excluded.

## tvOS — Apple TV

- CloudKit save syncing with iOS on correctly provisioned builds.
- LAN uploads for saves, mods, and game data.
- LAN save downloads and validated JSON uploads.
- Uploaded JSON settings apply after restarting, with previous settings retained.

Install the tvOS IPA using a compatible signing method. Start file transfer in the app and open its displayed LAN address on a phone or computer on the same trusted network.

Choose the appropriate upload category. JSON uploads must contain a valid JSON object, use a simple `.json` filename, and be no larger than 8 MB. Fully close and reopen the app to apply uploaded JSON settings. Save conflicts are reviewed in the app rather than silently overwriting active progress.

tvOS does not expose an iCloud Drive user folder. It uses CloudKit for saves and LAN transfers for other files. Apple TV storage can be purged by the system, so retain save backups through CloudKit or LAN downloads.

## Apple signing and iCloud

**Generic unsigned IPAs have CloudKit disabled.** Re-signing an IPA with an ordinary personal profile does not grant access to another developer team's iCloud containers.

To enable cloud support with your own Apple developer account, build with containers owned by your team and provision both app identifiers correctly. iOS and tvOS must use the same CloudKit container and environment, and the devices must be signed into the same iCloud account. Enable **Sync Saves with iCloud** in both apps. iOS iCloud Drive mirroring uses a separate Documents container.

See the [cloud signing and setup guide](https://github.com/linkzenic/Shipwright-Ports/blob/apple-platform-parity/docs/APPLE_CLOUD_SIGNING.md).

## Mods and support

Place compatible `.otr` or `.o2r` packs in the `mods` directory inside the active SOH user folder. On Apple TV, use the LAN upload page. Follow each pack's compatibility and activation instructions.

Report port-specific problems in [this repository's Issues](https://github.com/linkzenic/Shipwright-Ports/issues). Include your device, OS version, exact app version, reproduction steps, and whether mods are enabled. Remove personal information from logs before sharing them. Never upload ROMs or extracted game archives.

## Credits and development

Ship of Harkinian is developed by **Harbour Masters and its contributors**, building on the Ocarina of Time decompilation project and libultraship. Linkzenic maintains the platform adaptations in this repository.

- [Upstream source](https://github.com/HarbourMasters/Shipwright)
- [Official website](https://www.shipofharkinian.com/)
- [Credits](docs/CREDITS.md)
- [Building instructions](docs/BUILDING.md)
