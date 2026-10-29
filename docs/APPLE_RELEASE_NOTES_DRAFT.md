# Ship of Harkinian — Android, iOS, and tvOS

Brings all three ports together in one repository.

## Android

- Adds customizable Classic, N64, GameCube, and Modern touch layouts.
- Adds a layout editor with movable, resizable, and individually hideable controls.
- Adds independent touch assignments, manual-jump options, extra item buttons,
  modifier assignments, and floating-stick controls.
- Integrates item icons, contextual actions, Fairy, and Map controls into the touch layouts.

**Updating:** Install over your existing standard Ship of Harkinian app.

## iOS

- Adds customizable Classic, N64, GameCube, and Modern touch layouts.
- Adds a layout editor with movable, resizable, and individually hideable controls.
- Adds independent touch assignments, manual-jump options, extra item buttons,
  modifier assignments, and floating-stick controls.
- Integrates item icons, contextual actions, Fairy, and Map controls into the touch layouts.
- Adds automatic SOH user-folder syncing to iCloud Drive on properly provisioned
  builds, including saves, mods, and settings.
- Supports CloudKit save syncing with tvOS and preserves conflicting saves for review.

**Files:** Local copies remain available offline. External settings and resource
changes apply after restarting. Deletions do not automatically propagate.

## tvOS

- Supports CloudKit save syncing with iOS.
- Retains LAN uploads for saves, mods, and game data.
- Adds LAN save downloads and validated JSON uploads.
- Applies uploaded JSON settings after restarting, preserving the previous settings.

**Transfers:** Use LAN transfers on a trusted network and retain save backups.

**Apple signing:** Generic unsigned IPAs have CloudKit disabled. Cloud-enabled
builds require your own Apple developer account and matching iCloud container
provisioning. Setup instructions are included.

---

## Internal verification notes — omit from release body

- Adds the updated touch layouts and layout editor on iOS, including Classic,
  N64, GameCube, and Modern options.
- Automatically creates a visible SOH folder in iCloud Drive on correctly
  provisioned iOS builds, with automatic user-file mirroring and offline copies.
- Supports CloudKit save syncing between iOS and Apple TV when both apps are
  signed for the same user-owned CloudKit container and environment.
- Retains Apple TV LAN uploads for saves, mods, and game data, adds validated
  JSON uploads applied after restart, and provides save downloads.
- Preserves conflicting saves for review instead of silently choosing a winner.

**Signing:** Generic unsigned IPAs do not enable CloudKit. For cloud support,
build with your own Apple developer team's containers and sign both apps with
matching entitlements and provisioning profiles. See APPLE_CLOUD_SIGNING.md.

**Files:** iOS checks for changes while the app is active and on launch/foreground.
External JSON and resource changes apply at next launch. Deletions do not
automatically propagate. Runtime logs, caches, and sync bookkeeping are excluded.

**Apple TV:** Use the LAN transfer page only on a trusted local network. Fully
close and reopen the app after uploading JSON settings. tvOS storage can be
purged by the system; keep saves backed up through CloudKit or LAN downloads.

## Release preparation (not public notes)

- iPhone iCloud Drive visibility, automatic syncing and folder icon confirmed by user.
- tvOS CloudKit-enabled Release build and automated LAN/JSON tests passed.
- No further tvOS device test requested; live cross-device CloudKit is not verified.
- Still select final release version, production app IDs/signing/distribution mode,
  build release-named artifacts, and review these notes before publication.
- No preview bundles, personal provisioning profiles, credentials, or local paths
  should be included in public release artifacts.
