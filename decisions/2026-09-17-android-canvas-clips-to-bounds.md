# Android Canvas clips its content to declared bounds

- Date: 2026-09-17
- Status: accepted
- Issue: MOB-256

## Context

`Mob.Canvas` composites often draw geometry that extends past the
canvas's declared `width`/`height` and rely on the platform to clip the
overflow away. `MishkaSemiCircleProgress` (mob_mishka) is the canonical
example: it draws a full-radius arc centred at `(size/2, size/2)`
inside a Box whose height is only `size * 0.54`. The bottom half of
the arc is intentionally cropped so the reader sees a half-circle
gauge with a flat base.

iOS's SwiftUI `Canvas` clips its content by default; every canvas op
that draws past the view's bounds is masked away. On physical Moto G
Power (2026-09-17, MOB-246 verification pass) the same composite drew
its **full** circle straight through the caption `Text` in the
composite's `Column`. Compose's `Canvas` composable does not clip by
default.

Two rejected fixes chased the symptom instead of the cause:

- **Shift `startAngle` by 180°**: rotated the intended half-circle
  onto the other half. Displaced the broken overdraw rather than
  removing it — the arc still spilled past the canvas's declared
  height, still painted over the caption.
- **Negate `sweepAngle`**: same physical arc rendered on top of the
  same wrong half; overdraw unchanged.

## Decision

Add `.clipToBounds()` to the modifier chain on the Compose `Canvas` in
`MobBridge.kt.eex`'s `MobCanvas` composable. Every future `Mob.Canvas`
composite that relies on a clip — same shape as `MishkaSemiCircleProgress`
— now behaves consistently with iOS.

The `drawArc` handler stays exactly as it was on master
(`startAngle = startDeg, sweepAngle = endDeg - startDeg`) — `Mob.Canvas`
and Compose's `drawArc` already share the same numeric convention.

## Consequences

- iOS and Android now render `Mob.Canvas` composites with the same
  clipping semantics.
- Existing composites whose canvas ops all fit within the declared
  bounds are unaffected.
- Pinned by `MobBridge.kt Canvas clips ops to its bounds (MOB-256)` in
  `test/mob_new/project_generator_test.exs`. Removing either the
  `clipToBounds()` call or its import fails the test.
- No mob core or mob_mishka change required — the composite's contract
  was always correct; the platform renderer needed to match.

## Related

- MOB-246 (mob_mishka extraction epic) — surfaced this while
  screenshotting both physical devices side by side.
