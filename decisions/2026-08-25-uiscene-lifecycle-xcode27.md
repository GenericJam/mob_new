# Generated iOS apps must adopt UIScene lifecycle (Xcode 27 requirement)

- Date: 2026-08-25
- Status: accepted

## Context

Xcode 27 requires scene-based app startup for iOS apps. Mob-generated apps boot
everything — window creation, plugin registry, the BEAM-boot pthread — in
`AppDelegate.application:didFinishLaunchingWithOptions:`, which no longer works
under that requirement.

The fix was verified externally first, in the downstream app (commits `13dc2ab` +
`75ff1aa`), then ported here (MOB-97).

## Decision

- `AppDelegate`: drop the `window` property, reduce
  `didFinishLaunchingWithOptions:` to a bare `return YES;`. Every other
  AppDelegate method (orientation mask, push-token handlers) stays untouched.
- Add a `SceneDelegate` (same file) implementing
  `scene:willConnectToSession:options:` — creates the window via
  `initWithWindowScene:` and sets `rootViewController`/`makeKeyAndVisible` on
  **every** call (a scene can disconnect and later reconnect without
  relaunching the process), but wraps `mob_register_plugins()` /
  `mob_init_ui()` / the BEAM-boot pthread in a `static dispatch_once_t` — a
  second `erl_start` in the same process is fatal, and nothing in mob's native
  layer guards against it.
- `Info.plist`: add `UISceneConfigurations` (`UIWindowSceneSessionRoleApplication`
  → `SceneDelegate`) alongside the existing `UIApplicationSupportsMultipleScenes`.
- Generator tests (`project_generator_test.exs`) assert the rendered
  `AppDelegate.m` declares `UIWindowSceneDelegate` and calls
  `dispatch_once(&<token>, ...)` at the actual call site (not just the
  `dispatch_once_t` type declaration, which a careless "simplification" could
  leave behind after removing the real guard) — mirrors the house pattern set
  by `2026-06-17-android-16kb-page-size.md`.

## Consequences

- New apps from `mix mob.new` get scene-based startup out of the box.
- `AppDelegate.m` and `Info.plist` are app-owned (copied at generation), so
  **existing** apps need this hand-ported — it is not picked up by a dependency
  bump. `mob_plugin_demo` was hand-ported the same way (companion PR to
  MOB-97); any other pre-existing mob app needs the same treatment before
  building under Xcode 27. Port by hand from this template's
  `AppDelegate.m.eex` / `Info.plist.eex`, or reference the downstream app's
  `13dc2ab` + `75ff1aa`.
- Verified without Xcode 27 itself (beta, unavailable at the time of this
  change): `clang -fsyntax-only` against the rendered file on iOS Simulator
  SDK 26.5, plus a real `mix mob.deploy --native` to a physical iPhone SE
  (build, install, BEAM boot, app reaches its first screen) on a working
  baseline branch of `mob_plugin_demo`. Xcode 27's actual scene-adoption
  enforcement itself is unverified — re-check once it's out of beta.
