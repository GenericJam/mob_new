# Generated Android apps must support 16 KB memory page sizes

- Date: 2026-06-17
- Status: accepted

## Context

Google Play now requires apps targeting Android 15+ to support 16 KB memory page
sizes: every native `.so` LOAD segment must align to 16 KB (0x4000), not the
traditional 4 KB (0x1000). Io (livebook_mob) was approved on Play but flagged
"app does not support 16 KB memory page sizes".

Diagnosis (NDK `llvm-readelf -l <so>`, the LOAD `align` field): the prebuilt ERTS
binaries shipped as `lib*.so` (beam_smp, epmd, inet_gethost, …) were already
0x4000 from the OTP NDK build. Only the two libs the app's `build.zig` links
itself — `lib<app>.so` and `libsqlite3_nif.so` — were at 0x1000.

## Decision

Add `-Wl,-z,max-page-size=16384` to both NDK-clang `-shared` link steps in the
android `build.zig.eex` template (the `addLink` for `lib<app>.so` and the
sqlite3_nif link). A generator test asserts the literal appears on both links.

32-bit `armeabi-v7a` is exempt (16 KB pages are a 64-bit feature), so the flag is
harmless there and applied uniformly.

## Consequences

- New apps from `mix mob.new` (≥ 0.4.9) are 16 KB-clean out of the box.
- The `build.zig` is app-owned (copied at generation), so **existing** apps need
  the flag added to their own `android/app/src/main/jni/build.zig` — it is not
  picked up by a dependency bump. Io applied it directly.
- Third-party prebuilt `.so` (e.g. androidx.camera's `libimage_processing_util_jni`,
  ML Kit's `libbarhopper_v3`) can't be relinked — they must be removed (drop the
  dep) or bumped to a 16 KB-aligned version. The template ships no such deps by
  default; this is an app-level concern when adding camera/scanner/etc.
- Verify with: `llvm-readelf -l <so> | awk '/LOAD/{print $NF; exit}'` → `0x4000`.
