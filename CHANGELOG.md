# Changelog

All notable changes to **mob_new** (the project generator for Mob) are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html).

Full module documentation: [hexdocs.pm/mob_new](https://hexdocs.pm/mob_new).

---

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
