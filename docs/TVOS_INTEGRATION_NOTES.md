# tvOS parity integration

The transfer and navigation changes adapt the useful portions of
[Apple-platform PR #1](https://github.com/linkzenic/Ship-of-Harkinian-iOS/pull/1)
and [engine PR #1](https://github.com/linkzenic/libultraship/pull/1), contributed
by acwilan. The existing engine pin and project-owned dependency URLs remain
unchanged. The current shared Apple scene-lifecycle implementation is retained.

## Changes

- Prefer physical LAN interfaces over bridge/other IPv4 interfaces; reject
  tunnel, cellular, peer-to-peer, loopback, link-local and multicast addresses.
- Wait briefly after a successful HTTP response send before closing the
  connection, allowing the browser to complete its upload request.
- Keep tvOS controller navigation active when its setting is enabled,
  including startup transfer dialogs.
- Generate the tvOS CloudKit runtime marker from the actual build option.

## Local checks

```sh
c++ -std=c++20 -fsanitize=address,undefined \
  tests/android_touch_hud/tvos_network.cpp -o /tmp/soh-tvos-network-check
/tmp/soh-tvos-network-check
xcrun --sdk macosx clang++ -std=c++20 -fobjc-arc \
  tests/tvos_file_transfer/response.mm -framework Foundation -framework Network \
  -o /tmp/soh-tvos-response-check
/tmp/soh-tvos-response-check
DEPLOYMENT_TARGET=15.0 SOH_ENABLE_ICLOUD=OFF scripts/configure-ios.sh --tvos-simulator
cmake --build build-tvos-sim --target soh --config Release -- \
  -sdk appletvsimulator -destination 'generic/platform=tvOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

The response test uses a loopback listener and verifies a complete 128 KiB
response through the production send/close path. It does not write app data.

Validated locally on October 28, 2026:

- Interface-selection assertions passed with address/undefined sanitizers.
- The loopback HTTP response test passed.
- The transfer source compiled against the arm64 tvOS device SDK.
- A clean tvOS 27 simulator Release build succeeded with CloudKit disabled;
  its bundle contains the scene delegate and the correct false CloudKit marker.
- The app displayed the transfer dialog and served its web page with HTTP 200.
- A game-data archive and a save uploaded successfully with HTTP 201 responses.
- Relaunching with the uploaded archive reached the animated title sequence.

Controller interactions and physical Apple TV behavior are not established by
these automated simulator/HTTP checks.

## Release gates

Physical-device testing must cover the advertised LAN URL, browser upload
completion, Rescan/Exit controller focus, game startup, audio, save/relaunch,
and suspend/resume. Simulator and host tests do not establish hardware parity.

Save durability remains unresolved: current tvOS data lives in a purgeable
cache directory. These changes do not move data or claim that changing a local
directory alone guarantees persistence. Save sync/export and recovery behavior
need their own platform-specific validation before release.
