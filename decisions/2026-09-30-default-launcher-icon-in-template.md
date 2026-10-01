# Generated projects ship a default launcher icon
- Date: 2026-09-30
- Status: accepted

## Context
`AndroidManifest.xml.eex` declares `android:icon="@mipmap/ic_launcher"`, but
the generator shipped no mipmap resources. Icons came only from
`mix mob.install`, which writes mob_dev's bundled Mob logo when a platform has
none. Skip that step and the first `mix mob.deploy --native` fails in AAPT
("resource mipmap/ic_launcher not found"), which reads as a toolchain fault
rather than a missing file (MOB-106, duplicate MOB-148). iOS did not fail —
mob_dev runs `actool` only when `ios/Assets.xcassets/AppIcon.appiconset`
exists — but `Info.plist` names `AppIcon` and the app showed a blank icon.

## Decision
Ship the Mob logo as static files in `priv/static/mob.new/`:

- Android: `res/mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png` at 48/72/96/144/192
  px. **Legacy PNGs only, no adaptive icon.** On API 26+ a
  `mipmap-anydpi-v26/ic_launcher.xml` takes precedence over the PNGs, and
  `mix mob.icon` without `--adaptive` rewrites only the PNGs. A default
  adaptive icon would make that command silently stop changing the visible
  icon on every modern device. With legacy PNGs, `mix mob.icon` replaces
  them and `mix mob.icon --adaptive` layers an adaptive icon on top. No mob_dev
  change is needed.
- iOS: `Assets.xcassets/AppIcon.appiconset` with one 1024×1024 `universal`
  image (Xcode 14+ single-size icon). mob_dev's `actool` call uses
  `--minimum-deployment-target 17.0` and generates every size from it.
  `mix mob.icon` overwrites `Contents.json` with its full size table, so it
  replaces this set completely.

The PNGs are mob_dev's `priv/mob_logo/*.png` re-encoded from 16-bit to 8-bit
per channel (ImageMagick `-depth 8 -strip`): about 320 KB in total instead of
1.1 MB for the same sizes. The 1024 image has no alpha channel, as App Store
validation requires.

## Consequences
- A generated project builds natively on both platforms without
  `mix mob.install`.
- `mix mob.install`'s placeholder step is now a no-op for new projects
  (`MobDev.IconGenerator.platforms_missing_icons/1` finds `mipmap-mdpi/ic_launcher.png`
  and `Contents.json`). It still writes icons for projects generated before
  this change.
- The logo exists twice: in mob_dev's `priv/mob_logo/` and here. A logo
  change has to update both.
- Legacy icons on modern Android launchers are drawn inside the launcher's
  mask shape at a reduced size. That is the same icon `mix mob.install`
  produced before.
- Replacing the icon needs the `image` dep, which mob_dev declares optional
  and generated projects don't include: `mix mob.icon --source` raises
  without it, and a bare `mix mob.icon` falls back to writing the same Mob
  logo. The generated docs say to add `{:image, "~> 0.54"}` first.
