# Apple user-folder sync preview

## User-facing design

- iOS automatically opens its entitled iCloud Documents container and creates a
  visible SOH folder. If unavailable, Settings offers a document-picker fallback.
- The local user directory remains the offline working copy. Regular user files,
  including Save, mods, JSON configuration, archives, and nested files, reconcile
  on launch, foreground, completed game saves, and once per foreground minute.
- Runtime logs, caches, temporary/hidden files, symlinks, Conflicts and SaveSync
  bookkeeping are excluded. Missing files do not propagate deletions.
- External non-save changes are staged and applied before configuration/resources
  initialize on the next launch. Invalid JSON or changed local contents prevent
  replacement. Prior contents are retained in local history.
- First-time differences and two-sided changes preserve both copies. Save choices
  are per slot. Non-save conflicts retain local/cloud snapshots in the visible
  Conflicts folder as well as local bookkeeping; they are not silently applied.
- CloudKit remains the automatic save transport between iOS and tvOS. It uses
  content baselines and conditional record writes, not timestamp winner selection.
- tvOS exposes an IP-address web page for uploads and allowlisted save downloads.
  Save uploads are staged rather than overwriting a running game's save.
- Nearby pairing/Send/Receive controls have been removed from Settings. No nearby
  listener starts automatically. Existing review helpers remain internal.

## Provisioning

The existing CloudKit container is `iCloud.com.shipofharkinian.shared`.
The dedicated iOS Documents container is `iCloud.com.linkzenic.soh.documents`.
Keeping Documents separate avoids mixing user-folder contents with other ports
that already use the shared CloudKit container.

iOS profiles must authorize both identifiers, CloudKit and CloudDocuments, plus
the Documents ubiquity-container entitlement. tvOS needs only CloudKit and the
shared container. Both apps must use compatible CloudKit environments and the
same user's iCloud account for cross-device saves.

The iOS preview now has an explicit development profile authorizing both
containers. The user confirmed visible SOH folder creation, automatic file sync,
and the app icon in Files after preview build 4. Container access uses the explicit
Documents identifier from NSUbiquitousContainers. Status distinguishes local
container copies from uploads confirmed by the iCloud provider.

The tvOS Release target builds successfully with SOH_ENABLE_ICLOUD=ON and the
CloudKit-only entitlement template. No further Apple TV device testing was
requested. This build check is not verification of a signed distribution profile
or end-to-end cross-device CloudKit synchronization.

The unsigned IPA packager disables SOHCloudKitProvisionedBuild by default. Its
explicit SOH_PACKAGE_CLOUD=provisioned mode preserves cloud support for subsequent
signing with an authorized profile. See APPLE_CLOUD_SIGNING.md. Personal signing
cannot authorize another development team's containers. Users building with their
own developer team must configure their own shared CloudKit container for both
apps, enable cloud support, and provision both identifiers accordingly. Do not
advertise CloudKit as working in the generic unsigned IPA.

## Tests

`tests/apple_save_sync/policy.cpp`: reconciliation decisions and path exclusion.
`tests/apple_save_sync/user_folder.mm`: production folder uploads, archives/mods,
staged external JSON, conflict preservation and invalid-JSON rejection on a local
test filesystem (not a live File Provider).
`tests/tvos_file_transfer/download.mm`: production HTTP save download, empty slots,
and rejection of non-save filenames over loopback.

Not verified: provider/offline edge cases, CloudKit cross-device reconciliation
and account switching, and automatic mirroring with realistic large graphic packs.
The user waived further Apple TV device testing. LAN saves/mods/game archives and
save downloads are implemented. JSON uploads are now implemented with an 8 MB cap,
safe filenames, object validation, restart-only application and scoped history.
Production-handler loopback tests cover acceptance, malformed JSON, path rejection,
safe restart application and preservation of prior settings. No release has been
published for this work.
