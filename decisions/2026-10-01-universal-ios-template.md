# Generated iOS apps are universal, rotate and join Split View

- Date: 2026-10-01
- Status: accepted (supersedes the 2026-09-06 "tablets are not in scope"
  call on MOB-165)

## Context

`ios/Info.plist.eex` declared no `UIDeviceFamily` and no iPad keys, so a
generated app ran on iPad in iPhone compatibility mode: MOB-165 measured
`Mob.Test.screen_info/1` at 320x480 on a 13-inch iPad Pro, and the app never
resized. iPhone Duo (iOS 27.1, MOB-200) adds Split View on iPhone and an
inner display that is regular-width like an iPad, and Apple's guidance is that
apps should resize rather than pin orientation. MOB-206 asks the template to
opt in.

Checked against Xcode 27.0: the iOS 27.0 SDK defines device families `1`
(iPhone) and `2` (iPad) only (`SDKSettings.plist` `DeviceFamilies`). Whether
27.1 adds one for Duo is unknown; no value is invented.
`UIRequiresFullScreen` is deprecated since iPadOS 26 (TN3192).

## Decision

The template plist declares:

- `UIDeviceFamily` `[1, 2]`;
- `UIRequiresFullScreen` `false`, so the app can resize and join iPad Split
  View and Slide Over (`false` is the same as no key; it is written out so
  the intent is visible next to the keys that depend on it);
- all four orientations in `UISupportedInterfaceOrientations` (unchanged) and
  in a new `UISupportedInterfaceOrientations~ipad`.

`mob.exs` sets `ios_target_devices: [:iphone, :ipad]` and
`ios_orientations: :all`. mob_dev stamps those into the built bundle,
overriding `ios/Info.plist` (mob_dev
`decisions/2026-10-01-ios-layout-plist-keys.md`), so an app opts out of iPad
or locks orientation by editing one line, and the same keys work for apps
generated before this change. With a mob_dev that predates the keys they are
ignored and the plist defaults apply.

## Consequences

- New apps run full-screen on iPad and rotate there; on iPhone the only
  change is the `~ipad` key, which iPhone ignores.
- An App Store app built from the template ships iPad support, so it needs
  iPad screenshots and can't drop iPad in a later update. The `mob.exs`
  comment says so and shows the `[:iphone]` opt-out.
- Layout that assumed a fixed iPhone viewport is now reachable on resize;
  size classes (MOB-204) are the signal screens should use.
