# Android navigation: slide over a window copy of the outgoing screen
- Date: 2026-11-27
- Status: proposed (spike, branch `spike/nav-snapshot-material`)

## Context

MOB-146 (`2026-09-05-android-navigation-preserves-identity.md`) gave Android
one mount point that a navigation updates in place, which took a push on a
1600-node screen from 794ms to 374ms. Its recorded trade was the transition:
the outgoing screen vanished on the first frame and the incoming one slid in
over the background. A user reported it as flashing
(gitlab.com/MegaJ/mob-exploration#1), and `adb screenrecord` showed worse:
the incoming screen was drawn in place for one frame before its slide began,
because the `LaunchedEffect` that parked it off-canvas runs after that frame.

Every navigation convention (Material, Navigation Compose, Navigation 3, iOS)
keeps the outgoing screen visible for the whole transition. The stock ways to
do that in Compose (`AnimatedContent`, `NavHost`) mount the incoming screen as
a second, fresh tree, which is the rebuild MOB-146 removed; keeping the
outgoing tree mounted instead cost 122ms on every re-render, because a parked
Compose subtree recomposes with the active one until MOB-162 makes it
skippable.

## Decision

- When a navigation lands, `MobNavHost` keeps composing the screen already on
  display, as the same `ShownScreen` instance so `NavScreen` skips it, and
  copies the window with `PixelCopy`. A temporary log confirmed the held tree
  is not recomposed while the copy is taken.
- In one frame, the copy goes on top (or under, for a push) and the incoming
  tree replaces the outgoing one in the single mount point, exactly as in
  MOB-146. The copy then animates against the live incoming tree.
- The clock starts only after the incoming tree's first draw. Started before
  it, the animation spent its first ~150ms inside the build frame and the
  outgoing screen vanished in one jump (moto g power 2021). Fragment and
  Activity transitions postpone to pre-draw for the same reason.
- Motion: slide over. A push slides the incoming screen over the outgoing one
  from the right while the outgoing one shifts a quarter-width left; a pop
  reverses it; a reset cross-fades the copy away over the opaque incoming
  screen. 400ms on `md.sys.motion.easing.emphasized`.

### Material's shared axis, tried first

`MaterialSharedAxis(X)` (30dp travel, outgoing fades out over the first 35%,
incoming fades in over the rest, 450ms) was built first. It is a fade-through:
for two to three frames both screens are nearly transparent, and a dark header
went from near-black to the background colour and back in ~100ms (header
luminance 55 → 191 → 55 on the moto e and the moto g power 2021). On device
that read as a flash. The slide over has no opacity in a push or pop; its
recording has no frame below the screens' normal contrast, and on device no
flash was visible.

## Measurements

moto g power 2021 and moto e, Android 11 / 10, 720px wide, 60Hz, small screens
(mob-exploration):

| | moto g power 2021 | moto e |
| --- | --- | --- |
| window copy | 18–24ms, 39–63ms first | 21–32ms, 58ms first |
| frame interval during the transition | ~16.7ms | ~16.7ms |
| frames below normal contrast | 0 | 0 |

Tap to first movement on the 2021 (one sample each): 117ms with only the
first-frame fix, 184ms with the copy, the difference being the copy plus the
postponed start.

Also recorded on the 2021, with a throwaway lab screen: `pop_to_root` from
depth 3, `reset_to` (cross-fade, luminance rising monotonically, no dip),
`reset_to … transition: :push`, a pop with the keyboard up (the IME slides
down over the copy sliding off), a push interrupted by a pop or a second push
150ms in, a sheet and an alert (native animations, untouched), and a rotation
during a push. No frame fell below normal contrast in any of them.

## Consequences

- A navigation shows its first movement ~20–60ms later than before.
- One 720×1600 ARGB copy (4.6MB) per navigation, dropped when the transition
  ends.
- `Mob.RenderStats` would have timed the held frame, not the incoming build,
  and reported navigations cheaper than a re-render: the artifact the
  2026-09-05 record warns about. A navigation's sample is now parked in
  `setRootJson` and armed by `MobNavHost` (`MobBridge.navigationComposing`)
  when it lets the incoming tree compose, so `apply_us` brackets the build
  frame as before and excludes the copy, which is logged under the `MobNav`
  tag instead. A navigation superseded during its copy records no sample.
- A predictive-back preview needs the previous screen's pixels; this copy is
  the mechanism it would use. Not built.
- The direction is not mirrored for right-to-left layouts, as before.
- iOS is unchanged: it keeps two slots and slides both live trees.
- A navigation that interrupts a transition copies whatever is on screen,
  blend included, and runs its own transition from there. A pop 150ms into a
  push therefore snaps the half-started push back and plays a full pop rather
  than reversing it, as iOS does. No flash, but more motion than needed.
- A copy is drawn only at the size it was taken at: a rotation or resize
  mid-transition drops it, and the platform's rotation animation covers the
  switch.
- Cold launch is not covered by any of this: the window shows black
  (`styles.xml`), then `StartupStatus` on a stock dark scheme, then the app's
  theme once the BEAM pushes it (2.7s, 1.7s and 1.9s on the 2021). That is
  its own flash; the fix is a cached theme applied at `onCreate`.
- Not measured on a dense (1600-node) screen. The copy costs per pixel, not
  per node, and the held tree does not recompose, so neither should grow with
  the node count; the incoming build does, as it did before.
