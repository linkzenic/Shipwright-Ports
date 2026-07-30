# iOS Testing and Improvement Notes

This document records device-testing observations and the status of the
improvement pass authorized on 2026-07-29.

## Open observations

### IOS-001: Menu fonts look unclear and feel out of place on iOS

- **Area:** Menus / typography / display scaling
- **Status:** Implemented candidate; device review required
- **Observed:** Text throughout the interface feels strange and lacks clarity on
  the iPhone display.
- **Expected:** Menu text should be crisp, legible, and visually appropriate on
  iOS while retaining the Linkzenic SOH identity.
- **Current context:** SOH menus are rendered through the game's ImGui interface,
  not native UIKit controls, so they do not automatically use the iOS system
  font.
- **Investigate later:** Font-atlas resolution, Retina display scaling,
  filtering, glyph rasterization, bundled font selection, and whether an
  iOS-specific font or typography preset is desirable.
- **2026-07-29 change:** Increased the iOS ImGui font-atlas rasterization
  density for the default, Font Awesome, Montserrat, and Inconsolata fonts.
  Native UIKit fonts were not substituted because these menus are part of
  Linkzenic SOH's cross-platform ImGui interface.
- **2026-07-29 device result:** The denser atlas alone is not sufficient on the
  current point-resolution presentation surface; menu text remains visibly
  poor and difficult to read. A dedicated native-resolution iOS presentation
  path for the existing Linkzenic menu draw data is now required. Rebuilding
  the settings as a separate UIKit menu is rejected because it would duplicate
  and eventually drift from Linkzenic's menu items, options, and CVars.
- **2026-07-29 native-resolution fix:** SDL created the expected `3x` Metal
  drawable but ImGui's SDL2 backend left `DisplayFramebufferScale` at `1x`.
  The renderer consequently rejected the composite due to mismatched
  dimensions. The iOS path now supplies the actual renderer-output-to-logical
  window ratio each frame. Simulator testing verifies a `956x440` logical
  layout rendered into a `2868x1320` drawable at a matching `3x3` framebuffer
  scale with visibly sharp text.

### IOS-002: Menus are difficult to scroll using touch

- **Area:** Menus / touch input / navigation
- **Status:** Implemented candidate; device review required
- **Observed:** Navigating long menus on the iPhone is difficult because the
  interface does not respond naturally to touch scrolling.
- **Expected:** Dragging one finger over scrollable menu content should move the
  menu vertically, with behavior that feels natural on iOS. Inertial scrolling
  should be considered.
- **Interaction requirements:** A drag that begins on ordinary menu content
  should scroll, while taps and deliberate adjustments to sliders, checkboxes,
  combo boxes, and other controls should continue to work. Menu gestures must
  not activate or reposition gameplay touch controls.
- **Investigate later:** ImGui touch-to-mouse translation, drag threshold,
  scrolling speed, inertial deceleration, nested panes, scrollbar interaction,
  and gesture ownership between menu and gameplay input.
- **2026-07-29 change:** Added touch-drag scrolling for ordinary ImGui menu
  content with a touch-appropriate drag threshold. Active widgets retain their
  direct manipulation behavior. Inertial scrolling remains a possible
  refinement after device feedback.

### IOS-003: Shoulder buttons are oversized and do not match Android

- **Area:** Gameplay touch controls / layout / controller parity
- **Status:** Implemented candidate; device review required
- **Observed:** The on-screen L, R, and Z shoulder controls feel too large. The
  Android arrangement of paired `ZL`/`L` and `ZR`/`R` controls is not present.
- **Expected:** Restore the Linkzenic Android shoulder layout and mappings, with
  a smaller visual and touch footprint suitable for the iPhone display.
- **Verified current state:** Android exposes four distinct controls: `L` maps
  to the left shoulder, `ZL` to the left trigger, `ZR` to the right trigger, and
  `R` to the right shoulder. The current iOS overlay exposes only three:
  `L` maps to the left shoulder, `Z` to the left trigger, and `R` maps to the
  right trigger. The distinct right-shoulder control and the Android labels and
  paired arrangement were therefore lost in the initial iOS implementation.
- **Investigate later:** Copy the Android control grouping and mappings exactly,
  then tune button dimensions, spacing, safe-area placement, and minimum
  comfortable hit targets for iPhone.
- **2026-07-29 change:** Restored four distinct Android-parity controls and
  mappings (`ZL`/`L` and `ZR`/`R`) and reduced their visual footprint and
  spacing for iPhone.

### IOS-004: Right-stick touch behavior is invisible and unclear

- **Area:** Gameplay touch controls / camera
- **Status:** Fix implemented; device review required
- **Observed:** There is no visible right-stick control, and dragging on the
  right side of the screen produces no observable camera or right-stick
  response during device testing.
- **Verified current state:** The iOS overlay provides an invisible drag area
  over the right portion of the screen. Moving a finger there sends relative
  right-stick X/Y input for camera or free-look behavior, then returns both axes
  to neutral when the touch ends. It is not a visible or position-based virtual
  stick, and the intended input is not currently reaching an observable game
  action.
- **Code-review lead:** Touch free-look initialization is currently guarded by
  `__ANDROID__`, excluding iOS. The iOS virtual controller also needs to be
  checked for the same explicit SDL controller mapping used by Android. These
  are investigation leads, not yet confirmed as the sole cause.
- **Expected behavior to decide later:** Retain the unobstructed swipe-to-look
  surface, add discoverability feedback, or provide a floating right stick that
  appears at the touch location. Any choice should preserve access to face and
  C-button controls and match the intended Linkzenic Android behavior.
- **Investigate later:** Free-look settings, right-stick aiming and ocarina
  mappings, gesture sensitivity, simultaneous touches, visible feedback, and
  conflicts with nearby buttons.
- **2026-07-29 change:** Added the explicit SDL virtual-controller mapping used
  by the Android implementation so right-stick and trigger axes reach SOH's
  control deck. Replaced the invisible relative look surface with a floating,
  position-based right stick that appears at the initial touch location on the
  right side and hides on release.

### IOS-006: Touch D-pad does not produce D-pad input

- **Area:** Gameplay touch controls / D-pad
- **Status:** Fix implemented; device review required
- **Observed:** Pressing the visible directional cross produces no expected
  D-pad action.
- **Cause:** The four iOS touch regions were incorrectly connected to the
  right-stick X/Y axes even though the virtual controller declared the proper
  D-pad button mappings.
- **2026-07-29 change:** Connected the four regions to virtual buttons 11–14
  (`D-pad Up`, `Down`, `Left`, and `Right`), matching Linkzenic Android.

### IOS-005: Game rendering looks muted compared with the AYN Android build

- **Area:** Graphics / rendering quality / color
- **Status:** Partially improved; native Retina output remains open
- **Reference:** The same Linkzenic SOH build running on the AYN device looks
  richer and more impressive than the current iPhone 17 Pro Max build.
- **Observed:** The iPhone image feels muted and does not appear to take
  advantage of the display or device capability.
- **Additional device observation:** The problem is most severe in the menu,
  but the game image also feels horizontally or vertically squished and its
  colors appear less vibrant than expected.
- **Expected:** With equivalent game content and settings, the iPhone output
  should be at least as clear, vibrant, and polished as the AYN reference while
  preserving intentional game artwork and avoiding artificial oversaturation.
- **Comparison requirements:** Capture the same scene, camera position, time of
  day, mods, enhancement settings, internal resolution, and brightness on both
  devices before drawing conclusions.
- **Investigate later:** Metal drawable and texture color spaces, sRGB versus
  linear conversions, framebuffer format, display color management, internal
  render resolution, Retina/native output scaling, texture filtering,
  anti-aliasing, brightness and contrast, aspect-ratio scaling, and whether the
  two installations currently use identical graphics CVars and resource packs.
- **Next comparison:** Validate menu sharpness separately from the game
  framebuffer, then measure the final game viewport against the iPhone's usable
  safe-area aspect ratio and compare BGRA8 linear versus sRGB presentation.
- **2026-07-29 change:** Enabled ProMotion eligibility and game-oriented white
  point behavior in the iOS bundle. A first native Retina drawable change
  exposed a logical-point versus native-pixel mismatch in the current
  SDL/Metal/ImGui path and presented a black frame, so that flag was rolled
  back immediately. The corrected build renders successfully; proper native
  Retina output now requires a coordinated drawable, viewport, and input
  scaling change rather than a window flag alone.
- **2026-07-29 follow-up:** The missing ImGui framebuffer scale was identified
  and corrected in simulator testing, allowing native Retina presentation
  without a black frame. Physical-device review is pending. Aspect-ratio
  fitting and Metal color-space behavior remain separate open items.
- **2026-07-29 viewport follow-up:** Desktop pixel-perfect or integer-scale
  settings can request a game presentation rectangle larger than the iPhone's
  logical viewport. iOS now aspect-fits that final rectangle to the available
  screen while preserving the native-resolution game framebuffer and crisp
  Retina menu rendering.
- **2026-07-29 device-sizing correction:** Device logs confirmed a `956x440`
  logical ImGui viewport and `2868x1320` Metal drawable. The native drawable
  dimensions were incorrectly reused as the ImGui dockspace size, making the
  game layout three times larger than the display. iOS now uses logical points
  for the dockspace and game presentation rectangle, while multiplying the game
  render target by the detected framebuffer scale to retain native quality.
- **2026-07-29 menu settings:** The iOS menu-scale range is now `0.35x–1.0x`
  instead of the desktop-oriented `0.65x–2.5x`. The “Open App Files Folder”
  action is hidden on iOS because iOS does not permit opening the app container
  as a normal filesystem folder.

### IOS-007: Shared saves across Apple devices

- **Area:** Storage / CloudKit / platform expansion
- **Status:** iPhone implementation candidate; provisioning and device review
  required
- **Goal:** Let one user continue the same SOH save on iPhone, iPad, Apple TV,
  and a future Mac build without forcing every device to share large game
  archives or inappropriate display and input settings.
- **2026-07-29 change:** Added opt-in CloudKit synchronization for
  `Save/global.sav` and the three game save slots. The app compares source
  modification dates at startup, retains a conflict backup before replacing a
  different local save, uploads atomically committed local changes, and defers
  mid-session cloud downloads until restart.
- **Deliberate boundary:** `soh.o2r`, extracted data, mods, caches, logs, and
  device-specific configuration stay local. CloudKit is used instead of iCloud
  Drive so the same sync layer can operate on tvOS.
- **Device validation:** Enable **Sync Saves with iCloud**, save a game, use
  **Sync Saves Now**, restart, and confirm the status reports that saves are
  current. Test first with backed-up save files. Confirm that disabling the
  option causes no CloudKit startup wait or upload.

### IOS-008: iPad compatibility

- **Area:** Universal app / layout / touch controls
- **Status:** Simulator build and launch validated; game-data and physical-device
  review required
- **2026-07-29 change:** The iOS target declares both iPhone and iPad device
  families. Safe-area layout remains adaptive, and iPad permits a larger touch
  control scale without changing the Android-parity mappings.
- **2026-07-29 validation:** A Release arm64 simulator build installed and
  launched on a 13-inch iPad Pro simulator. The native-resolution first-run
  prompt rendered successfully and the app remained running.
- **Remaining:** Import a valid O2R on the simulator or a physical iPad and
  verify gameplay viewport fitting, multitouch, rotation policy, controller
  input, suspend/resume, and CloudKit with an actual iCloud account.

### IOS-009: Apple TV compatibility and local file transfer

- **Area:** tvOS / controllers / storage
- **Status:** tvOS build validated; runtime and physical-device review required
- **2026-07-29 change:** Added tvOS simulator and device build modes, Apple TV
  bundle metadata, controller-first navigation, shared CloudKit save sync, and
  a Bonjour-advertised HTTP uploader on port 8080.
- **Transfer boundary:** Game archives, legally acquired ROMs, and mods upload
  to local app storage. Only `Save/global.sav` and `Save/file1.sav` through
  `Save/file3.sav` participate in CloudKit synchronization. Settings JSON,
  controller mappings, display configuration, logs, and caches stay local.
- **Safety:** Uploads are streamed in chunks, limited to 4 GB, restricted to
  supported file extensions, and atomically installed only after completion.
- **2026-07-29 validation:** A Release arm64 tvOS Simulator bundle compiled and
  linked successfully. Its plist declares Apple TV device family 3, Metal,
  indirect input, and extended gamepad support. The final bundle contains
  `soh.o2r` and the extractor `assets/` directory.
- **Remaining:** This Mac does not currently have a tvOS Simulator runtime
  installed. Install that runtime or use a physical Apple TV to validate
  launch, the displayed transfer URL, browser upload/rescan, Bonjour discovery,
  Siri Remote behavior, paired gamepads, CloudKit provisioning, and background
  lifecycle behavior. Final layered Apple TV app-icon and top-shelf artwork
  are also still required for distribution.

### TVOS-010: Extraction dialogs cannot be activated with TV input

- **Area:** tvOS / first-run extraction / focus navigation
- **Status:** Open observation; do not implement yet
- **Observed:** Buttons displayed during ROM extraction behave like desktop
  mouse targets. The Siri Remote and game controller cannot focus or activate
  them reliably.
- **Expected:** Every first-run, extraction, error, and confirmation action must
  participate in tvOS focus navigation and respond to the Siri Remote select
  button and standard controller confirm/cancel inputs. A mouse must never be
  required.
- **Investigate later:** ImGui controller-navigation focus assignment, automatic
  default focus when a modal opens, Siri Remote select/back mapping, controller
  A/B mapping, and replacing any remaining desktop-only modal behavior with a
  controller-first tvOS presentation.

### TVOS-011: Dusklight-style television menus

- **Area:** tvOS / settings UI / focus navigation
- **Status:** Long-term improvement; do not implement yet
- **Direction:** Replace the desktop-oriented settings presentation on Apple TV
  with a Dusklight-style, focus-first television interface. The design should
  use large readable rows, clear selection states, predictable directional
  movement, and controller/Siri Remote conventions while retaining the full
  Linkzenic SOH option set.
- **Current decision:** Keep the improved ImGui controller navigation for now;
  it is sufficient for ongoing device testing.
