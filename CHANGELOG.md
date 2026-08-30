# Changelog

All notable changes to **mob_new** (the project generator for Mob) are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html).

Full module documentation: [hexdocs.pm/mob_new](https://hexdocs.pm/mob_new).

---

## [0.4.29] - 2026-08-31

### Fixed
- **Android: a replacement sheet no longer inherits its predecessor's hidden
  or already-dismissed state.** The generated sheet renderer keys presentation
  state (visibility + the exactly-once dismissal flag) by the sheet node's
  `id`, canonicalized across every JSON id form (string, number, boolean,
  explicit null, array, object — key order irrelevant; `""`, `0`, `false`,
  and `null` are all distinct from an absent id, which keeps the previous
  slot-scoped behavior). A replaced sheet's presentation is deactivated on
  disposal, so a late dismiss callback can neither hide the new sheet nor
  suppress its `{:dismiss, tag}`; re-renders that keep the same `id` update
  content in place without re-presenting. Ships generated instrumentation
  coverage (`SheetIdentityTest`). A narrow dismiss-races-re-render window
  remains until mob's generation-tagged event handles land (mob#114, in
  revision) — this fix never widens it.

## [0.4.28] - 2026-08-30

### Fixed
- **0.4.27's published package could not compile.** The compile-time Zig-pin
  reader loaded the repository-root `.tool-versions`, which Hex omits from
  packages, so a clean compile of the published artifact raised `File.read!`.
  The pin now ships in `priv/zig-version` (included in the package), a
  lockstep test guards drift against the repo's `.tool-versions`, and a
  packed-archive regression builds and installs the archive from real
  unpacked Hex source. Use 0.4.28 instead of 0.4.27.

## [0.4.27] - 2026-08-30

### Fixed
- **Generated projects pin the Android Zig toolchain.** `.tool-versions` now
  includes `zig 0.17.0-dev.269+ebff43698` (derived at compile time from
  mob_new's own pin), so a first `mix mob.deploy --native` no longer fails
  toolchain detection on Android. LiveView-generated projects, which
  previously received no `.tool-versions`, now get one too; an existing
  `.tool-versions` is never clobbered. The generated header notes that the
  zig dev pin requires mise (asdf cannot fetch historical nightlies).
  Companion to mob_dev 0.6.29's corrected install guidance.

## [0.4.26] - 2026-08-29

### Fixed
- **Generated Android bridge now exposes `MobBridge.screenInfo()`.** Mob's
  optional JNI binding (`nif_screen_info`, mob 0.7+) expects a static
  `screenInfo(): FloatArray` returning `[w, h, density, top, bottom, left,
  right]` in dp; generated bridges omitted it, so `Mob.Test.screen_info/1`
  returned all zeros on Android. Uses `currentWindowMetrics` +
  `getInsetsIgnoringVisibility(systemBars | displayCutout)` on API 30+, with a
  `decorView`/`rootWindowInsets` fallback below. Template lint rejects
  generated bridges that omit or misplace the entrypoint. Existing apps must
  regenerate or hand-port the bridge to pick this up.

## [0.4.25] - 2026-08-27

### Added
- **Generated Android intrinsic Sheet support.** The renderer parses typed
  content detents from the JSON array, hugs short content, caps against the
  configured `max_height` and the current parent constraint, and applies
  internal vertical scrolling to overflow. `:medium`/`:large` behaviour is
  unchanged.
- **Generated Android composite Box accessibility.** `accessibility_label`
  becomes `contentDescription`, an explicit button role is preserved even with
  no tap handle, `disabled` semantics are exposed, disabled interaction does
  not dispatch, and a passive labelled Box does not become a button.

### Fixed
- **A content Sheet containing a scrollable child crashed the app.** The
  content-detent path wrapped the sheet body in `verticalScroll`
  unconditionally, and Compose throws when a scrollable is measured with an
  infinite max height — so a `scroll` or `lazy_list` inside `detents:
  [:content]`, the most natural use of an intrinsic sheet, died at first
  measure with `IllegalStateException: Vertically scrollable component was
  measured with an infinity maximum height constraints`. The sheet now only
  adds its own scroll when the content has none; the height cap applies either
  way and the child keeps owning its scrolling.
- A disabled Box dispatched taps unless it also carried an explicit button
  role, while simultaneously reporting `disabled()` semantics — announced as
  disabled to TalkBack and still firing. iOS disables every Box regardless of
  role, so this was also a platform split.
- A Box declared `accessibility_role: :button` whose tap is handled by an
  ancestor was announced as "button, disabled", because Compose publishes
  disabled semantics whenever `clickable`'s `enabled` is false.
- The Sheet height cap sat outside the node's own padding, so a padded sheet
  overshot `max_height`; iOS caps the already-padded body.

### Changed
- **Generated projects now require `{:mob, "~> 0.7.32"}`** (was `"~> 0.7.31"`).
  Intrinsic Sheet detents and composite Box accessibility only reach the
  generated Android renderer because mob 0.7.32 validates and encodes them; on
  an older mob those props never arrive and the behaviour silently degrades.

## [0.4.24] - 2026-08-27

### Added
- **Android Sheet renderer** — `Mob.UI.sheet/2` now renders on Android as a
  Material 3 `ModalBottomSheet`, matching the iOS `.sheet` primitive that
  shipped in mob 0.7.29. Supports `:detents` (medium-only sheets included),
  `:background`, `:scrim` (applied exactly, unlike iOS where the system owns
  dimming opacity), `:corner_radius`, and the custom drag indicator props.
  Until now `Mob.UI.sheet/2` was an iOS-only primitive in practice: generated
  Android apps had no sheet case at all and rendered nothing.

### Fixed
- **Sheet dismissal delivers `{:dismiss, tag}`, not `{:tap, tag}`.** The
  renderer routed dismissal through `MobBridge.nativeSendTap`, but
  `Mob.UI.sheet/2` documents `:on_dismiss` as `{:dismiss, tag}` and iOS
  delivers that. A screen written to the documented contract never matched:
  `Mob.Screen` forwards the unmatched message to `handle_info`, raising
  `FunctionClauseError` and killing the screen process — or a catch-all
  swallowed it, leaving the BEAM unaware the sheet had closed and unable to
  re-present it. Adds the `nativeSendDismiss` extern on `MobBridge` and the
  matching `beam_jni.c` thunk (MOB-104).
- **`detents` was never read from real BEAM data.** `detentsProp` cast
  `props["detents"] as? List<*>`, but JSON array props arrive as
  `org.json.JSONArray`, which is not a Kotlin `List` — so the cast always
  failed and every sheet silently fell back to `["medium", "large"]`. The
  medium-only detent could only ever trigger from a hand-built `MobNode` in a
  test. Now branches on `is JSONArray`, the pattern already proven for `:tabs`.

### Changed
- **Generated projects now require `{:mob, "~> 0.7.31"}`** (was `"~> 0.7"`).
  The generated Android `beam_jni.c` calls `mob_send_dismiss`, which mob only
  exports from 0.7.31. With the looser constraint an older mob resolved fine
  and then failed late in `mix mob.deploy --android --native` with
  `call to undeclared function 'mob_send_dismiss'`.

### Upgrading
- **Existing Android projects need a hand-port.** `MobBridge.kt` and
  `beam_jni.c` are app-owned and never re-rendered, so regenerating is not
  enough. `mix mob.doctor` (mob_dev) warns when a project still carries the
  old wiring and prints the two-line change. If you worked around the old
  behaviour by matching `handle_info({:tap, tag}, ...)` for a sheet dismissal,
  that clause is now dead — switch it to `{:dismiss, tag}`.

## [0.4.23] - 2026-08-26

### Fixed
- **Generated Android `MobNativeViewRegistry.render()` didn't guard the
  MOB-100 exhaustion sentinel.** mob 0.7.28 fixed native component handle
  pool exhaustion by returning a `-1` sentinel (instead of crashing) when
  the pool is full; iOS's `MobNativeViewRegistry.view(for:)` was updated
  to skip rendering on `-1`, but the generated Android template's
  `render()` still treated any non-null `component_handle` as valid,
  wiring up a native view against an unregistered handle. Now mirrors
  iOS: `if (handle < 0) return`.

## [0.4.22] - 2026-08-26

### Fixed
- **Android JNI owner mismatch for tier-2 native components.**
  `MobBridge.kt.eex` declared `nativeDeliverComponentEvent` as a bare
  `external fun` on `MobNativeViewRegistry`, but the generated JNI export
  is `Java_<pkg>_MobBridge_nativeDeliverComponentEvent` — JNI resolves a
  native method by its declaring class, so a real event from a Compose
  native component threw `UnsatisfiedLinkError`. Moved the declaration
  onto `MobBridge` as `@JvmStatic external fun`, matching every other
  `nativeDeliver*` callback in the file. Added
  `MobNew.Templates.Lint.native_funs_owned_by_mob_bridge/1` (wired into
  the standard `check_kotlin/1` lint pass) — the existing
  `external_fun_jni_consistency/2` only checked that Kotlin and C agreed
  on the function NAME, not which class actually owned the Kotlin
  declaration, so it stayed green through this exact bug; the new check
  is brace-depth aware, catching a native fun nested inside another
  class within `object MobBridge` too, not just one declared on an
  entirely different object. (MOB-98)

## [0.4.21] - 2026-08-25

### Added
- **Generated `MobBridge.kt`'s font resolver now walks mob's font
  fallback chain**, part of the mob custom-fonts feature (see
  [`mob`'s `MOB_FONTS.md`](https://github.com/GenericJam/mob/blob/master/MOB_FONTS.md)).
  `setTheme` parses the `_font_fallback` array pushed by
  `Mob.Theme.set/1` into `MobBridge.fontFallback`; `fontFamilyProp`'s
  `resolveOneFontName` walks `[the node's own font] + fontFallback` in
  order, trying each candidate (bundled `res/font/` resource first,
  then a raw system family name) until one resolves.

### Fixed
- **The fallback chain above never actually triggered a fallback.**
  `Typeface.create(String, Int)` never returns null and rarely throws
  for an unrecognized family name — per its own documentation it
  silently substitutes `Typeface.DEFAULT`. `resolveOneFontName`'s
  `try/catch` around it never caught this, so the first fallback
  candidate always "succeeded" (as the system default) and the walk
  never reached the real fallback font. Found via physical-device
  verification (Android emulator running Android 15) immediately
  after this feature's own device check — row C of the test screen
  showed the plain system font instead of the expected fallback.
  Now detects failure via reference-equality against `Typeface.DEFAULT`
  and logs + continues the walk instead. Re-verified on the same
  emulator: the fallback font renders correctly. (MOB-94)

## [0.4.20] - 2026-07-07

### Added
- **Scaffolded `MobBridge` audio-probe Kotlin methods** backing mob 0.7.18's
  `Mob.Audio` probes. `audioOutputStatus()` (volume / mute / route / other-audio
  via `AudioManager`) and `audioOutputLevel(source)` (peak/RMS dB from a
  short-lived `Visualizer` on `Mob.Audio`'s own player session, which works with
  `RECORD_AUDIO`; length-1 error codes the NIF maps to atoms). Plus mic
  `input_level` metering via `MediaRecorder.getMaxAmplitude` for the agent
  "ears" (MOB-35). Device-verified on a Moto G power (2021). (#25, #31)

---

## [0.4.19] - 2026-07-04

### Added
- **Generated `MobBridge` keep-awake method** for `Mob.Device.keep_awake/1`
  (mob 0.7.17). Generated Android apps get a `MobBridge.keepAwake(Int)` that
  toggles the window's `FLAG_KEEP_SCREEN_ON` on the UI thread — no permission.
  Adds the `android.view.WindowManager` import. Requires mob 0.7.17+.
  Device-verified on moto g power (2021). (MOB-20, #30)

## [0.4.18] - 2026-07-04

### Added
- **Generated Android network-connectivity callback** for
  `Mob.Device.network_state/0` (mob 0.7.16). `MainActivity` registers a
  `ConnectivityManager.NetworkCallback` that maps `NetworkCapabilities` to
  online / transport / expensive / validated and delivers the snapshot to the
  BEAM through a `beam_jni.c` trampoline (`nativeNotifyConnectivity` →
  `mob_send_connectivity_changed`); `onLost` re-queries the active network
  rather than assuming offline. Adds `ACCESS_NETWORK_STATE` to the manifest.
  Generator test covers the rendered extern / thunk / permission. Device-verified
  on moto g power (2021). (MOB-14, #28)
- **`mob_audio_capture` pre-trusted in generated apps** so the plugin activates
  without a manual trust prompt. (MOB-34, #29)

## [0.4.17] - 2026-07-04

### Added
- **Generated `MobBridge` torch method** for `Mob.Torch` (mob 0.7.15). Generated
  Android apps get a `MobBridge.torch(String)` that toggles the rear-camera torch
  via `CameraManager.setTorchMode` — no capture session, no `CAMERA` permission.
  It finds a camera with a flash unit, no-ops on flash-less devices, and swallows
  transient camera-access failures. Adds a not-required `android.hardware.camera.flash`
  `<uses-feature>` so flash-less devices still install. Requires mob 0.7.15+.
  Device-verified on moto g power (2021). (MOB-15, #27)

## [0.4.16] - 2026-07-04

### Added
- **Generated `MobBridge` registers the magnetometer / compass path** for
  `Mob.Motion`'s `:magnetometer` sensor (mob 0.7.14). `motion_start` parses the
  requested sensor set out of its spec arg and, only when `:magnetometer` was
  asked for, registers `TYPE_MAGNETIC_FIELD` + `TYPE_ROTATION_VECTOR` and routes
  through the new `nativeDeliverMotionMag` JNI thunk (with the matching
  `beam_jni.c` binding to `mob_deliver_motion_mag`). Accel/gyro-only apps keep
  the byte-identical 3-key path. Requires mob 0.7.14+. (MOB-6, #26)

### Added
- **`MobBridge.openSettings/1` scaffolding** for `Mob.Device.open_settings/1`
  (mob 0.7.8). Generated Android apps can now open an OS settings screen by
  target: `:app` (app details / permissions), `:notifications`, or
  `:exact_alarm` (with the correct SDK 31+ guard and a fallback to the app
  page). iOS needs no companion (the NIF opens the single app settings page).

## [0.4.14] - 2026-06-25

### Added
- **Device-orientation lock works out of the box.** Generated apps now ship the
  companion native hooks that `Mob.Device.lock_orientation/1` /
  `unlock_orientation/0` need to actually hold a rotation (mob 0.7.7+):
  - iOS: `AppDelegate` returns `mob_locked_orientation_mask()` from
    `application:supportedInterfaceOrientationsForWindow:` (the window-level
    override that holds the lock over the root view controller), and `Info.plist`
    declares the landscape + upside-down `UISupportedInterfaceOrientations`.
  - Android: `MobBridge.orientationLock/1` → `setRequestedOrientation`, and
    `MainActivity.onConfigurationChanged` forwards rotations to the BEAM via a
    `nativeNotifyOrientation` → `mob_send_orientation_changed` JNI thunk, so
    `Mob.Device.orientation/0` and the `:display` subscription track rotations.

## [0.4.13] - 2026-06-24

### Added
- **The generated demo's theme picker now offers Material 3 and Liquid Glass**
  alongside Light and Dark (a 2×2 grid). "Material 3" applies
  `MobThemes.Material3` (M3 baseline palette + shape scale); "Liquid Glass"
  applies `MobThemes.ObsidianGlass`, which renders real `glassEffect` translucent
  surfaces on iOS 26+ (`.ultraThinMaterial` fallback on iOS 17–25). Both themes
  already shipped in the `mob_themes` dependency; this just wires them into the
  picker. The new tabs are gated behind the showcase (non-`--blank`) build, so a
  `--blank` app, which doesn't depend on `mob_themes`, stays clean and keeps just
  Light/Dark.

### Fixed
- **Tapping a local notification now brings the generated Android app to the
  foreground.** The template's `NotificationReceiver.onReceive` built and posted
  the notification but never set a content intent, so the tap was a no-op in
  every scaffolded app. It now attaches a `PendingIntent` that relaunches
  `MainActivity` (singleTop) carrying the payload under `mob_notification_json`
  — the exact key `MainActivity.onCreate`/`onNewIntent` already read to forward
  it to the BEAM. A `ProjectGeneratorTest` case asserts the rendered
  `MobBridge.kt` wires `setContentIntent` + `PendingIntent.getActivity` + the
  payload key, so the template can't silently regress. Verified end-to-end on a
  physical device. (#23)

  Known limitation (not fixed here): for *local* notifications, a warm tap
  forwards the payload on the next screen mount rather than to the live screen,
  since `MobBridge.notifyPid` is only set by the push-registration path. The tap
  reliably foregrounds the app; live in-app delivery on a warm tap needs
  separate core/host plumbing.

---

## [0.4.11] - 2026-06-19

### Changed (default scaffolding)
- **Generated Android apps no longer ship a foreground service or Firebase by
  default.** Removed the `dataSync` `BeamForegroundService`, the FCM
  `MobFirebaseService`, the `google-services` plugin/classpath + firebase
  dependency, the placeholder `google-services.json`, the FGS permissions, and
  the `MobBridge` background-keep-alive methods from the template. Both drew
  Google Play policy scrutiny (unused `dataSync` FGS / `c2dm` permissions) on
  apps that used neither. They are now opt-in: background keep-alive via the
  `mob_background` plugin, FCM via the `mob_notify` plugin (whose `gradle_dep`
  auto-merges; the host service + `google-services` are documented
  `host_requirements`). `POST_NOTIFICATIONS` stays (local notifications).

---

## [0.4.10] - 2026-06-19

### Added
- **`build.zig` links plugin `:cpp_archive` static libs** via
  `-Dplugin_static_libs` across the android JNI, iOS sim, and iOS device
  templates — pairs with mob_dev 0.6.10's cpp_archive plugin path. (#22)
- **`mix mob.new` scaffolds a `Mob.ScreenCase` test** for the generated home
  screen (`test/<app>/home_screen_test.exs`), pairs with mob 0.7.2. (#21)

---

## [0.4.9] - 2026-06-17

### Fixed
- **Generated Android apps now support 16 KB memory page sizes** (Google Play
  requirement on Android 15+). The android `build.zig` links `lib<app>.so` and
  `libsqlite3_nif.so` with `-Wl,-z,max-page-size=16384`, so their LOAD segments
  align to 16 KB. Without it, Play rejects the AAB with "app does not support
  16 KB memory page sizes". The prebuilt ERTS `lib*.so` were already 16 KB-aligned
  by the OTP NDK build; only the two zig-linked app libs needed the flag. Pinned
  by a generator test. (Apps generated before 0.4.9 need the flag added to their
  app-owned `android/app/src/main/jni/build.zig`.)

---

## [0.4.5] - 2026-06-16

### Added
- **Android x86_64 emulator slice in generated apps** (resolves GenericJam/mob#20).
  `build.gradle` abiFilters gains `x86_64` + `OTP_RELEASE_X86_64`; `CMakeLists.txt`
  and `build.zig` handle the x86_64 ABI. Pairs with mob_dev 0.6.4's x86_64 OTP
  runtime, so generated apps run on x86_64 emulators (Intel / CI hosts).

## [0.4.4] - 2026-06-16

### Added
- Generated `mob.exs` ships `config :mob, :trusted_plugins` with the shared mob
  first-party signing-key fingerprint for all official plugins. The bundled
  showcase plugins (now signed on Hex) clear the signature gate out of the box —
  no `acknowledge_unsafe_plugins` needed — and any other first-party plugin a
  user activates is pre-trusted.

## [0.4.3] - 2026-06-15

### Fixed
- **Android `build.zig`: wire `erts`/`jni` imports for plugin zig NIFs.** The
  plugin-zig-NIF compile path passed `.mob_dir` to `addZigObject`, but the
  `ZigObjectOptions` struct had no such field and the helper never wired the
  `@import("erts")` / `@import("jni")` named modules a plugin NIF needs — so any
  app activating a zig-NIF plugin (camera/location/biometric all ship one)
  failed to build for Android. Added the field + module wiring (mob_erts.zig /
  mob_zig.zig, std-only + PIC). Found + fixed verifying the showcase on a
  physical Android phone.

## [0.4.2] - 2026-06-15

### Added
- **Showcase plugins by default.** Generated apps now depend on `mob_camera`,
  `mob_location`, `mob_biometric`, and `mob_themes`, activate them in `mob.exs`
  (`config :mob, :plugins` / `:styles` / `:default_style`), and the home screen
  enumerates `Mob.Plugins.screens/0` to auto-list each plugin's demo screen — so
  a fresh app demonstrates real device capabilities out of the box (the mob
  analogue of `mix phx.new` shipping Ecto). Remove any plugin from `mix.exs` +
  `mob.exs` to drop it; the home list and native build adjust with no other edits.

### Fixed
- `--local` (path-dep) generation now marks the `:mob` path dep `override: true`,
  so a local mob checkout satisfies the `mob ~> 0.7` requirement the Hex showcase
  plugins declare (Mix won't otherwise use a path dep for a Hex sub-requirement).

## [0.4.1] - 2026-06-12

### Fixed
- The sample `CameraScreen` template survived the 0.4.0 capability strip while
  its native half didn't — generated apps warned on the removed `Mob.Camera`
  core API and would crash on that screen. Removed the screen and its home
  nav entry (caught by the published-archive smoke test).

## [0.4.0] - 2026-06-12

### Changed
- **Generated apps target mob 0.7 / mob_dev 0.6** (the plugin-extraction majors).
- **Templates stripped of the extracted capabilities** — camera capture/frame-stream Kotlin, camera/scanner/notify code, media-read + notification permissions, the scanner `<activity>`, and the preset-theme switcher (now Light/Dark baseline; presets ship in the `mob_themes` style package). The plugins re-supply each via their manifests on activation.
- iOS plugin objc NIFs build with Apple clang (`addObjcObject`); Android `build.zig` gains the `plugin_zig_nifs`/`plugin_jni_sources` options.
- Notification delivery state rides the generated `io.mob.plugin.MobNotifyHub` (host code and the `mob_notify` plugin share it without cross-package references).

### Fixed
- Dead dotfile templates deleted (byte-diff-proven); `.credo.exs` now actually ships in archive-generated apps (it was silently dropped by the archive's dotfile-excluding wildcard); the inline `.tool-versions` pins Elixir 1.20.0 final (was rc.5 — the on-device stdlib-skew version).

## [0.3.16]

### Fixed
- **Generated Android apps are now shippable to Play out of the box.** The `android/app/build.gradle` template was missing three things every release build needs, so a freshly generated app crashed or got rejected at the Play Store (all three hit while shipping a real app):
  - **`useLegacyPackaging true`** (new `packagingOptions { jniLibs { … } }` block). AGP defaults release App Bundles to `extractNativeLibs=false`, leaving native libs packed in the APK — but the BEAM `dlopen`s `lib<app>.so` by absolute path and execs `inet_gethost`/`epmd` as real processes, so they must be on the filesystem. Without this the app crashes on launch on a Play-installed split (`dlopen … library not found`); debug builds default to `true`, which masked it.
  - **Release `signingConfigs`** reading `android/keystore.properties` (generated by `mix mob.setup.google_play`), wired into `buildTypes.release` — otherwise the release AAB is unsigned and Play rejects it.
  - **`compileSdk`/`targetSdk` 34 → 35** — Play requires API 35 for new apps and updates.

## [0.3.15]

### Added
- **Test-harness driving in `MobBridge.kt.eex` (Kotlin side of mob #40; companion to mob 0.6.23).** Generated apps gain the bridge methods mob's Zig NIFs call so a remotely-connected agent can capture, scroll, and locate elements over Erlang dist with no `adb`: `screenshot(format, quality, scale)` (`PixelCopy` → PNG/JPEG bytes, decor-view `draw` fallback pre-API-26); an id-keyed `ScrollHandle` registry with `scrollInfo(id)`/`scrollTo(id, x, y)` (`pixel` for `ScrollState`/`verticalScroll`, `index` for `LazyListState`); and `frameTrackingModifier(id)` (`testTag` + `onGloballyPositioned`) feeding `elementFrames()` → JSON `{id:[x,y,w,h]}` in dp. Opt-in per `:id`; untagged nodes get no tracking modifier. Registries clear on navigation. Verified end-to-end on a moto g power (Android 11) via a generated app.
- **Android WebView handles HTML file inputs.** `MobWebView` wires `onShowFileChooser`, so `<input type="file">` in an embedded page now opens the system picker instead of silently doing nothing.

### Fixed
- **Bridge scroll/element-frame registries are now thread-safe.** `scrollHandlesById` and `elementFramesById` are written from the Compose main thread (registration / `onGloballyPositioned`) and read from the NIF/binder thread (`scrollInfo`/`scrollTo`/`elementFrames`). They were plain `mutableMapOf`, so a concurrent layout during a read could throw `ConcurrentModificationException`. Both are now `ConcurrentHashMap` (weakly-consistent iteration, no CME), and `scrollHandle/1` uses `computeIfAbsent` so a registration race can't drop a handle. (iOS already guarded its registry with `@synchronized`.)

## [0.3.13]

### Fixed
- **Generated `.credo.exs` now actually runs ex_slop.** The template registered `{ExSlop, []}` under `checks.enabled`, but ex_slop ≥ 0.4.2 is a Credo *plugin* — listed as a check it's ignored as an "undefined check" and runs *zero* ex_slop checks, silently (the build still passes, so the regression is invisible). Generated projects have had AI-slop linting disabled. Now registered under `plugins:`, with the dep pinned to `~> 0.4.2` (the plugin-API version) so config and version can't drift. A generator test pins it. (The mob/mob_dev/mob_new repos themselves are unaffected — they're on ex_slop 0.4.0, where ExSlop is still a check and the existing wiring is correct.)

## [0.3.12]

### Fixed
- **Generated `.gitignore` now excludes native build artifacts and signing secrets.** The template only ignored `_build`/`deps`/`*.beam`/`android/app/build/`, so a fresh project that ran a native build and then `git add -A` would commit `.cxx/` and `.zig-cache/` outputs, the bundled OTP zip (~19 MB), compiled `*.o`/`*.so`/`*.a`, and — worst — the Android signing keystore + `keystore.properties`. Both generation paths are covered: the bare-Mob `.gitignore` heredoc, and `patch_gitignore/1` on the LiveView path now appends the native-excludes block to Phoenix's own `.gitignore` (idempotent, sentinel-guarded). A generator test pins the critical patterns. Surfaced when pushing a fresh project to GitHub and finding build junk staged.

## [0.3.11]

### Fixed
- **Android WebView now fills its bounds** — `MobWebView` sets `MATCH_PARENT` layout params plus `useWideViewPort` / `loadWithOverviewMode`. The WebView previously defaulted to `wrap_content`, so any full-viewport page loaded into it (CSS `100vh` / `100%` — e.g. an embedded xterm.js terminal) measured its container as 0px and rendered blank. Surfaced while building a terminal-in-mob proof-of-concept; fix verified on a physical Android device (xterm.js terminal renders and accepts input). iOS WKWebView is unaffected — it's sized by its SwiftUI frame, so `vh` units already resolve.

## [0.3.10]

### Added
- **`MobBridge.kt.eex` ships `audio_play_at` and supporting WAV chunk walker.** Pairs with `Mob.Audio.play_at/4` in mob 0.6.17 — sample-accurate scheduled playback against the Android audio hardware clock via `AudioTrack` in `MODE_STREAM`. Coarse `Thread.sleep` + 3 ms busy-wait for sub-buffer-tick wakeup precision, `THREAD_PRIORITY_AUDIO` to favour scheduling, 64 KB chunked feed from `RandomAccessFile` so multi-MB stems don't load fully into memory. Per-device output-latency calibration via `AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER` / `PROPERTY_OUTPUT_SAMPLE_RATE`, cached after first probe.
- WAV header parser handles intermediate `LIST` / `INFO` chunks between `fmt ` and `data` — ffmpeg-generated WAVs often emit metadata chunks the naive "header is at byte 44" approach would skip.

### Fixed
- `audio_stop_playback` no longer bails early when no legacy `MediaPlayer` is active. Previously the `audioPlayer ?: return` short-circuit prevented the scheduled-track cleanup from running, so apps using `audio_play_at` exclusively had a Stop call that silently no-op'd on the audio path while the UI thought it had stopped.

## [0.3.9]

### Fixed
- **Android `build.zig.eex` template now exposes `tflite_static` as a `b.option`** and threads it into the `driver_tab_android` build options alongside `nx_eigen_static`. Without this, any newly-scaffolded project that adds a static NIF and runs `mix mob.regen_driver_tab` would fail to compile with `error: root source file struct 'options' has no member named 'tflite_static'` — the driver_tab generator unconditionally references `build_options.tflite_static`, but the template only declared `nx_eigen_static`. Asymmetry surfaced while wiring up a fresh rustler-using test app; the fix restores symmetry between the two guarded NIFs that mob_dev's StaticNifs defaults declare.

## [0.3.8]

### Added
- **`project_swift_sources` build hook on iOS templates.** Both `ios/build.zig.eex` and `ios/build_device.zig.eex` now accept `-Dproject_swift_sources=<absolute,paths>` — a comma-separated list of extra Swift sources to compile into the same `swiftc` invocation as Mob's bridge sources. Empty/unset is a no-op. Paired with `mob_dev`'s `:project_swift_sources` mob.exs key (mob_dev#6) so downstream apps can ship project Swift without patching the generator. Originally proposed by @dl-alexandre.
- `MobBridge.kt.eex`: `MobTextField` now honours `secure: true`. Applies
  `PasswordVisualTransformation()` to mask input and overrides the
  keyboard type to `KeyboardType.Password` (autocorrect off, no
  suggestions strip). Mirrors the iOS-side `secure` prop landing in
  mob 0.6.x. The Elixir cleartext still reaches the BEAM via
  `on_change` so apps hash/store the value as normal.

  Existing apps generated from prior templates are unaffected — the
  prop is a no-op there. Regenerating or hand-porting `MobBridge.kt`
  enables masking.

## [0.3.7]

### Added
- **MaterialTheme follows BEAM-side `Mob.Theme` out of the box.** Apps generated from `mix mob.new` now wire Compose's MaterialTheme to the BEAM-pushed theme so Material 3 system widgets (NavigationBar, Button, …) match whatever `Mob.Theme.set(...)` the host has active — no more white-on-light NavigationBar over a dark Obsidian / ObsidianGlass page. Two pieces:
  - `MobBridge.kt`: `setTheme(json)` JNI handler called by `mob 0.6.14`'s new `:mob_nif.set_theme/1`. Decodes the resolved palette JSON into a `mutableStateOf<Map<String, Long>?>` (Compose-observable; cross-thread-safe via a main-looper hop).
  - `MainActivity.kt`: reads `MobBridge.themeColors` and builds `darkColorScheme(...)` from it. Mob's `surface_raised` / `muted` map onto Material 3's `surfaceVariant` / `onSurfaceVariant` (same role). Stock `darkColorScheme()` covers the brief gap between `setContent` and the BEAM's first theme push.
- Requires `mob ≥ 0.6.14`. Older runtimes don't define the `setTheme` Bridge method or call the NIF, so MaterialTheme just stays on the fallback — no breakage, but the system widgets won't follow `Mob.Theme.set/1`.

## [0.3.6]

### Added
- **`Mob.Camera.start_frame_stream/2` Android support baked into the template.** Apps generated from `mix mob.new` now ship the Kotlin side (`camera_start_frame_stream`, `camera_stop_frame_stream`, `deliverFrame`, `centerCropAndScale`, `bitmapToRgbF32`, `bitmapToBgraU8`) plus the JNI thunk (`nativeDeliverCameraFrame`) wired through to `mob_deliver_camera_frame`. Prior to this, projects generated from `mob_new` ≤ 0.3.5 would fail at NIF load against `mob ≥ 0.6.8` — the new JNI bindings for `camera_start_frame_stream` / `camera_stop_frame_stream` are `cacheRequired`, so missing static methods caused the app to crash on launch.
- **`aspect_ratio` modifier prop** in `nodeModifier` (Android) — wraps `Modifier.aspectRatio(r)`. Useful for locking camera + canvas overlays to a 1:1 square so model-space coordinates align with the visible preview area.

### Fixed
- **`MobCameraPreview` Z-order and stability fixes** so Compose overlays (status text, bounding boxes, etc.) drawn on top of the camera actually render:
  - Switched `PreviewView` from default `ImplementationMode.PERFORMANCE` (SurfaceView, punches through above Compose and hides overlays) to `COMPATIBLE` (TextureView, renders inside the normal Compose Z-order).
  - Moved the camera bind out of `AndroidView.update` (which re-runs on every recomposition and caused continual `unbindAll` / `bindToLifecycle` cycles whenever any sibling state ticked — e.g. an FPS counter — making the surface flicker and fight with overlays) into a `LaunchedEffect(frameActive, cameraSelector)` keyed only on values that should trigger a rebind.
  - Added `Modifier.clipToBounds()` to the `AndroidView` wrapping the `PreviewView` so the surface texture can't bleed past its declared layout bounds.
  - `PreviewView.scaleType = FILL_CENTER` to match the model-side center-crop in `MobBridge.deliverFrame`, so overlay-canvas coords align with the preview underneath.
## [0.3.5]

### Fixed
- `beam_jni.c.eex`: restored the closing `}` for `nativeDeliverVendorUsbEvent`. Without it, clang sees nested function definitions and rejects every `JNIEXPORT` that follows ("function definition is not allowed here") — C compilation fails immediately on any project generated from 0.3.3/0.3.4.
- `MobBridge.kt.eex`: removed three duplicate imports (`IntentFilter`, `ConcurrentHashMap`, `AtomicInteger`). Each now appears exactly once in the alphabetised bottom-of-file import block. kotlinc was rejecting with "Conflicting import" so `gradleDebug` failed on any project generated from 0.3.3/0.3.4.
- `beam_jni.c.eex`: removed a 276-line duplicate Bluetooth Classic JNI block (lines 533-808 mirrored 256-531 verbatim). Caused "redefinition of `Java_..._MobBridge_nativeDeliverBt*`" errors at compile time. The canonical first block stays. (Surfaced by the new `clang -fsyntax-only` test below — string-match generator-test assertions still passed because the substrings exist, just twice.)

All three regressions were introduced by the 0.3.3 BT-PR merge taking the union of imports / blocks during conflict resolution, when the 0.3.2 fix had specifically de-duplicated them. Reported by external user on master 2026-05-17.

### Added
- `MobNew.Templates.Lint` — module of structural lints for generator-rendered native source files. 8 checks: `balanced_braces`, `balanced_parens`, `balanced_brackets`, `no_eex_leaks`, `unique_kotlin_imports`, `unique_swift_imports`, `external_fun_jni_consistency`, plus `check_kotlin/1` / `check_c/1` / `check_swift/1` aggregate functions. Returns a list of issue maps; empty list = clean. 25 unit tests cover each check red-then-green.
- Generator tests now use `Lint.check_kotlin/1` and `Lint.check_c/1` instead of inline brace-counting + import-dedup logic. Single source of truth; clearer failure messages.
- New cross-file consistency test: asserts every `external fun nativeFoo(...)` in MobBridge.kt has a matching `Java_..._MobBridge_nativeFoo(...)` JNI thunk in beam_jni.c. Catches "added the Kotlin side but forgot the C thunk" (or the reverse).
- New `clang -fsyntax-only` test (`@tag :requires_android_ndk`) that invokes the NDK's clang against the rendered `beam_jni.c`. Catches the full class of "actually broken C" — typos, wrong arg counts, duplicate definitions — that tier-1 structural lints can miss. Skips cleanly when the Android NDK isn't installed (mirrors the existing `:requires_zig` pattern).

## [0.3.4]

### Added
- `CLAUDE.md` "Release flow" section pointing at the canonical process
  in [`mob/RELEASE.md`](https://github.com/GenericJam/mob/blob/master/RELEASE.md)
  (URL form so it resolves without a local mob checkout). mob_new
  specifics: generator tests need `MOB_DIR=/Users/kevin/code/mob` set
  when running from a worktree (the resolver looks for `mob` alongside
  the project and the worktree path breaks that assumption).
- `.githooks/pre-push` — same script shipped in mob (cheap preflight
  always, release preflight when `mix.exs` changed). Activate per
  clone or worktree with `git config core.hooksPath .githooks`.

## [0.3.3]

### Added
- Bluetooth Classic peripheral codegen (`MobBridge.kt.eex`, `beam_jni.c.eex`, `AndroidManifest.xml.eex`) — generated apps now include the Kotlin BroadcastReceivers, JNI native_* externs, and Android permissions for the `Mob.Bt` runtime API (HFP / SPP / HID). Companion to `mob` 0.6.5's `Mob.Bt` module. Contributed by [@HeroesLament](https://github.com/HeroesLament) ([#4](https://github.com/GenericJam/mob_new/pull/4)).

## [0.3.2]

### Fixed
- HexDocs `source_url` and `source_url_pattern` pointed at the wrong repo (`mob` instead of `mob_new`) and at a non-existent `/mob_new/` subdirectory prefix; the rendered `</>` glyphs all 404'd. Corrected to `github.com/genericjam/mob_new/blob/master/...`.
- Template fix: `beam_jni.c.eex` was missing the closing `}` for `nativeDeliverVendorUsbEvent` before the BT JNI thunks began — every subsequent `JNIEXPORT void JNICALL` was rejected by clang with "function definition is not allowed here". Generator tests never caught this because they grep rendered output, not compile it.
- Template fix: `MobBridge.kt.eex` duplicated three imports (`IntentFilter`, `ConcurrentHashMap`, `AtomicInteger`) alongside the BT Bluetooth* imports; kotlinc rejected with "Conflicting import".
- Template fix: `MobBridge.kt.eex` missing `androidx.compose.foundation.layout.fillMaxSize` import for the GpuView compile-error overlay.
- Template fix: orphan comment in the import block confused ktlint's `import-ordering` rule (no autocorrect available when imports are interleaved with comments).

### Added
- `.github/workflows/test.yml` — runs `mix test`, `mix format --check-formatted`, `mix credo --strict`, and `mix deps.audit` on push to master and on every PR.
- `.github/workflows/release.yml` — on tag push, creates a GitHub Release whose body is the matching `## [X.Y.Z]` section from this changelog.

## [0.3.1]

### Added
- Bluetooth Classic template scaffolding: `MobBridge.kt.eex` gains the Kotlin BroadcastReceivers, `external fun nativeDeliver*` JNI declarations, and Compose wiring for the `Mob.Bt` runtime API (HFP / SPP / HID). `AndroidManifest.xml.eex` gains the matching modern + legacy Bluetooth permissions. `beam_jni.c.eex` gains the per-event JNI thunks. (Generator tests cover the rendered template's external strings; manual on-device verification per the CLAUDE.md convention.)
- `Mob.GpuView` Android backend (GLES 3.0): `MobBridge.kt.eex` gains `MobGpuView` composable + `MobGpuSurfaceView` + `MobGpuRenderer`, mirroring the iOS `MobGpuView.swift` shipped in mob 0.6.4. Same `%{ios: "...MSL...", android: "...GLSL ES..."}` cross-platform shader contract; std140-ish uniform packing matches the iOS Swift packer (scalar/vec2/vec4 with natural alignment). Translucent red compile-error overlay on shader failure, matching iOS behavior.
- Generator-test coverage for both surfaces — asserts the rendered template contains the expected composables, classes, imports, and dispatch entries.

## [0.3.0] and earlier

Earlier releases predate this changelog; consult the [tag list](https://github.com/genericjam/mob_new/tags) and the per-tag commit messages for history.
