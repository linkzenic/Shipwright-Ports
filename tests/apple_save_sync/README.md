# Apple save sync foundation

> The feature description below records the earlier LAN-pairing prototype, not
> the current UI. Pairing controls have been removed. Current behavior and signing
> requirements are in `docs/APPLE_USER_FOLDER_SYNC.md` and
> `docs/APPLE_CLOUD_SIGNING.md`. The legacy tests still cover shared save-review
> helpers. `tests/tvos_file_transfer/download.mm` additionally tests production
> HTTP downloads, JSON upload validation, path rejection, restart-only application
> and preservation of previous settings. These are local tests, not live CloudKit
> verification.

Run the transport-independent conflict policy tests:

```sh
c++ -std=c++20 -fsanitize=address,undefined tests/apple_save_sync/policy.cpp -o /tmp/soh-save-sync-policy
/tmp/soh-save-sync-policy
```

Run the production LAN transport and staged-save tests on macOS:

```sh
xcrun clang++ -std=c++20 -fobjc-arc -fblocks -fsanitize=address,undefined \
  -Itests/apple_save_sync/stubs -Isoh tests/apple_save_sync/nearby.mm \
  soh/ios/SOHSharedSaveFiles.mm -framework Foundation -framework Network \
  -o /tmp/soh-nearby-tests
/tmp/soh-nearby-tests
```

Settings exposes the Nearby Save Sync preview and automatic folder checks.
Folder checks run at launch/foreground and after completed game saves. They
are not an iOS background service. This is not release-ready yet.

Implemented:
- Three-way content comparison; no clock-based winner or automatic deletion.
- Save filename allowlist and bounded staged downloads with atomic metadata.
- iOS folder picker and persistent security-scoped bookmark access.
- Bonjour discovery and one-use six-digit pairing, five-attempt limit, bounded
  framed transfers, session token, ten-minute sharing timeout and background stop.
- Explicit Send/Receive, incoming slot list, Use Incoming/Keep Local choices.
- Safe application in SaveManager after joining its worker; newer local writes
  and ambiguous incoming versions are preserved instead of silently replaced.
- Coordinated iOS folder save checks and restart-only local mod imports.
- Both Apple device targets build; policy and loopback tests pass with sanitizers.

Device checklist:
- Start sharing on TV and pair from iOS; permit Local Network on both devices.
- Send and Receive independently; active saves must remain unchanged until
  Use Incoming returns to file select. Keep Local must retain local progress.
- Verify SaveSync/History preserves replaced saves and no nested Save path.
- Re-pair after backgrounding or expiry; wrong code/token must fail.
- Choose an iCloud Drive folder; verify Saves and Mods behavior with downloaded
  and provider-only files, revoked access, offline launch and storage exhaustion.
- Import mods during gameplay: visuals must not change until a full relaunch.
- Test simultaneous edits and multiple incoming copies of one slot.

Known preview limits:
- LAN transport is unencrypted and explicitly labeled for trusted LANs only.
  Tokens are session-only. Harden transport before general release.
- Either device may show a pairing code or enter the other device's code. The
  paired session supports Send/Receive from both ends. tvOS has six digit sliders.
- Incoming slots have independent choices with source and basic progress details.
  Multiple distinct candidates for a slot require Keep Local then re-receive.
- Folder setup creates SOH/Saves and SOH/Mods under the authorized location (or
  reuses a selected SOH folder). The system picker permission remains required.
- Folder downloads without a conflict apply at the next safe file-select boundary;
  differing first-time copies and two-sided edits require a choice. Previous
  content and ambiguous candidates are preserved.
- Automatic mod refresh skips unchanged size/date fingerprints and stages changed
  packs for next launch. No deletion propagation, background service or LAN mod
  transfer. Mod import currently supports top-level .otr/.o2r packs only.
- Legacy CloudKit controls remain for existing signed builds, but new save-sync
  operations refuse to run while that option is enabled.

Never log security-scoped bookmark data, pairing credentials, or user paths.
