# Android template on Kotlin 2.4.21 / AGP 9.3.3 / Gradle 9.7.0, strong skipping off

Date: 2026-10-22
Status: accepted
Ticket: MOB-497

## Context

The template pinned `kotlin-gradle-plugin:1.9.22`, which carries
CVE-2026-53914 (GHSA-r937-wjx7-w2jp): unsafe deserialization of build-cache
metadata, fixed in 2.4.20-Beta1 with no 1.9.x backport. Only the build is
exposed, not the shipped app, but that includes any developer or CI host using
a shared or remote Gradle build cache. Getting off 1.9 means Kotlin 2, where
the Compose compiler moves into the `org.jetbrains.kotlin.plugin.compose`
Gradle plugin and `composeOptions.kotlinCompilerExtensionVersion` goes away.

JetBrains' compatibility table for KGP 2.4.20–2.4.21 lists Gradle
7.6.3–9.7.0 and AGP 8.5.2–9.3.1, so AGP 8.2.0 / Gradle 8.2.1 had to move too.

## Decision

- **Kotlin 2.4.21**, the newest 2.4.x patch. `kotlin-gradle-plugin` and
  `compose-compiler-gradle-plugin` both sit on the buildscript classpath at
  that version; the Compose compiler plugin must match Kotlin exactly.
- **AGP 9.3.3**: the 9.3 line is the newest JetBrains tests KGP 2.4.21
  against (the table's ceiling is 9.3.1; AGP 9.4, though stable and fine
  with JDK 17 and compileSdk 35, is outside it). 9.3.3 deliberately goes two
  patches past that ceiling: 9.3.2 fixes lint crashing on JDK 17, which is
  the JDK `.tool-versions` pins, and 9.3.3 carries further R8/D8 fixes.
- **Gradle 9.7.0**, the top of KGP's tested range (AGP 9.3 needs 9.5+). The
  wrapper jar and `gradlew` were regenerated with it, not only the
  properties.
- **Built-in Kotlin.** AGP 9 compiles Kotlin itself, so `kotlin-android` is
  gone from `app/build.gradle`, and `kotlinOptions { jvmTarget }` became
  `compileOptions` at the same Java 8 target. Built-in Kotlin only brings KGP
  2.2.10, which is still vulnerable. **The explicit KGP classpath line is
  what carries the fix**; deleting it as redundant brings the CVE back.
- **Strong skipping disabled** through
  `composeCompiler { featureFlags = [ComposeFeatureFlag.StrongSkipping.disabled()] }`.
  The Kotlin 2 Compose compiler turns it on by default, which lets a
  composable with unstable parameters skip when it gets the same instances.
  The renderer was measured and tested without it (see
  `2026-09-05-android-navigation-preserves-identity.md`), and turning it on is
  MOB-162's job: it needs a before/after device measurement and a review of
  `LocalSlotEpoch`, which is a `compositionLocalOf` only because nothing
  skipped. A security bump should not change recomposition behavior on the
  side.
- Groovy `prop value` assignments that Gradle 9 deprecates (`namespace`,
  `ndkVersion`, CMake `version`, `compose`, `useLegacyPackaging`) now use
  `=`. mob_dev's `ndkVersion` reader already accepts both forms.

The K2 compiler built the template's Kotlin, and the default plugins'
`bridge_kt` sources (mob_camera, mob_location, mob_biometric), with no source
changes.

## Consequences

- Existing apps are not regenerated. The mob_dev half of MOB-497 adds a
  `mix mob.doctor` warning when the project's Gradle files pin Kotlin below
  2.4.20 (or run AGP 9 with no KGP declared), and does not patch them
  (mob_dev's `decisions/2026-08-25-detect-dont-autopatch-native-source.md`).
  It reaches users with the first mob_dev release after 0.7.29.
- MOB-162 now starts by removing the `StrongSkipping.disabled()` line, then
  measuring.
- AGP 9's new DSL is on (no `android.newDsl=false`). A plugin or user script
  that reaches for the old variant API (`applicationVariants`) fails at
  configuration time.
- An osv-scanner pass over the generated project's locked Gradle deps still
  reports advisories in AGP's own transitive build tooling (netty,
  bouncycastle, commons-lang3, jdom2, jose4j). Those are build-time
  dependencies of AGP 9.3.3 and are not fixed by this change.
