# AGP 9.3.3's build-time dependency advisories are accepted, not overridden

Date: 2026-10-22
Status: accepted
Follows: `2026-10-22-kotlin-2-agp-9-toolchain.md` (MOB-497)

## Context

With Gradle dependency locking turned on for both the buildscript classpath
and every `:app` configuration, osv-scanner 2.3.6 reports advisories in a
freshly generated app. None is in what the app ships: the
`debugRuntimeClasspath` / `releaseRuntimeClasspath` locks are clean. Every hit
is in tooling that AGP 9.3.3 resolves for itself and runs on the developer's
or CI machine.

How it was reproduced: generate an app, add
`configurations.classpath { resolutionStrategy.activateDependencyLocking() }`
inside `buildscript { }` and
`allprojects { dependencyLocking { lockAllConfigurations() } }` to
`android/build.gradle`, run `./gradlew buildEnvironment --write-locks` and
`./gradlew :app:dependencies --write-locks` on JDK 17, then
`osv-scanner scan source -L buildscript-gradle.lockfile -L app/gradle.lockfile`.

| Package | Advisories (fixed in) | Pulled in by | Runs during | Reachable |
|---|---|---|---|---|
| `bcprov-jdk18on` / `bcpkix-jdk18on` 1.79 | GHSA-574f-3g2m-x479 GOST-28147 CTR keystream reuse (1.80.2); GHSA-9pwp-9qqc-pr26 name-constraints bypass (1.85); GHSA-qp49-qgx5-5m26 ASN.1 nesting-depth guard reset (1.85); GHSA-c3fc-8qff-9hwx LDAP injection in `LDAPStoreHelper` (1.84); GHSA-wg6q-6289-32hp PKIX draft `CompositeVerifier` accepts empty signatures (1.84) | `sdk-common`, `builder`, `apkzlib` (classpath); lint (`androidLintTool`); UTP result listener | every build (signing, debug keystore); lint on `bundleRelease`; `connected*AndroidTest` | Library loaded, flawed code not reached: signing uses RSA/EC rather than GOST, builds no LDAP stores or composite signatures, and does no name-constrained path validation. The ASN.1 parsing covers the developer's own keystore and certificates. |
| `commons-lang3` 3.16.0 | GHSA-j288-q9x7-2f5v `ClassUtils.getClass` recursion → `StackOverflowError` (3.18.0) | `commons-compress` ← `sdklib`; lint; UTP result listener | every build; `connected*AndroidTest` | Only reachable as a crash on a build-local, very long class name. No attacker input. |
| `jdom2` 2.0.6 | GHSA-2363-cqg2-863c XXE in `SAXBuilder` (2.0.6.1) | `jetifier-processor` 1.0.0-beta10 | Jetifier only | No: the template does not set `android.enableJetifier`. |
| `jose4j` 0.9.5 | GHSA-3677-xxcr-wjqv JWE decompression DoS (0.9.6) | `bundletool` 1.18.3 | `bundleRelease` | No: bundletool uses jose4j for code-transparency JWS. AGP never asks it to decrypt a JWE. |
| `httpclient` 4.5.6 | GHSA-7r82-7xv7-xcpj malformed-authority URI misparse (4.5.13) | lint; UTP result listener | lint on `bundleRelease`; `connected*AndroidTest` | No: lint and the result listener talk only to fixed URLs, never to attacker-supplied ones. |
| `netty-*` 4.1.93 / 4.1.110 (codec, codec-http, codec-http2, handler, handler-proxy, common) | 40 distinct advisories (HTTP/1 smuggling, HTTP/2 resets, SNI/TLS handler, decompression DoS, Windows-only DoS), fixed in 4.1.94–4.1.137 | `grpc-netty` in the Unified Test Platform (`unified-test-platform-core`, `…-host-emulator-control`) | `connected*AndroidTest` / managed devices only | Not in `assembleDebug`, `bundleRelease` or `mix mob.deploy`. The test run uses gRPC over loopback between Gradle and the UTP process, so only a local attacker could reach it. |

`./gradlew --dry-run` confirms the task split: `assembleDebug` runs no lint
or UTP task, while `bundleRelease` runs `lintVitalAnalyzeRelease`.

## Decision

- **Stay on AGP 9.3.3.** It is the newest 9.3.x on Google Maven. AGP 9.4.1,
  the newest stable release, would clear 41 of the 49 advisory ids: AGP
  9.4 replaces the grpc/netty UTP launcher with `android-test-engine` 1.0.1,
  which drops netty entirely, and `sdk-common` 32.4.1 moves Bouncy Castle to
  1.80.2, which fixes the GOST advisory. Rescanning a generated app with AGP
  9.4.1 leaves 8 findings: Bouncy Castle 1.80.2 (four, needing 1.84/1.85),
  commons-lang3, httpclient, jdom2 and jose4j, because `bundletool` 1.18.3 and
  `jetifier-processor` 1.0.0-beta10 are unchanged. It is held back anyway,
  because KGP 2.4.21's tested AGP range ends at 9.3.1. 9.3.3 goes two patch
  releases past that for lint and R8 fixes; going to 9.4 would mean a new
  minor line that JetBrains has not tested, and the netty findings it removes
  are confined to instrumented test runs. 9.5 is still a release candidate.
  Kotlin 2.5.0 is in beta.
- **No `buildscript { dependencies { constraints { classpath(...) } } }`
  override.** The only patch-level fixes, `jdom2` 2.0.6.1 and `jose4j`
  0.9.6, are for code a normal build never runs. Bouncy Castle 1.79→1.85 and
  commons-lang3 3.16→3.18 are minor bumps under Google's signing and SDK
  code, for issues that code does not reach. A buildscript constraint also
  misses the lint and UTP configurations, which AGP resolves inside the app
  project, so scanners would still report most of the findings.
  Forcing versions under AGP would put every generated app on a build Google
  never tested to quiet a scanner, and users would carry that drift.

## Consequences

- An osv-scanner pass over a locked generated project keeps reporting these
  findings. They are expected and are not a regression in the template.
- Revisit when a stable Kotlin release lists AGP 9.4 (or later) in its
  tested range. That bump removes the netty and GOST findings and should be
  made as a toolchain change with build proof. Revisit sooner if an advisory
  turns out to be reachable from a normal build, for example a template that
  enables Jetifier or a CI recipe that runs `connectedAndroidTest` on a
  shared host.
