# Changelog

All notable changes to **mob_new** (the project generator for Mob) are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html).

Full module documentation: [hexdocs.pm/mob_new](https://hexdocs.pm/mob_new).

---

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
