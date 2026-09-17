# Compose arc handler must not run angles through dp→px

- Date: 2026-09-17
- Status: accepted
- Issue: MOB-256

## Context

The `arc` handler in the generated Compose bridge (`MobBridge.kt.eex`) used
`canvasFloat` to unpack every field on a `%{op: :arc, ...}` map, angles
included:

```kotlin
val startDeg = canvasFloat(op["start_deg"])
val endDeg   = canvasFloat(op["end_deg"])
```

`canvasFloat` is the helper that converts BEAM-side canvas coordinates
(quoted in dp — the same unit the canvas's declared `width` and `height`
use) into DrawScope pixels via `dp.dp.toPx()`. Applying it to `start_deg`
and `end_deg` scales the angles by the device density.

On the Moto G Power (2021) at density 1.75, `MishkaSemiCircleProgress`'s
`arc(centre, centre, radius, 180, 360, …)` reached `drawArc` as
`startAngle = 315f, sweepAngle = 315f`, and its 72% indicator
`arc(centre, centre, radius, 180, 309.6, …)` became
`startAngle = 315f, sweepAngle = 226.8f`. `MishkaAngleSlider`'s
`arc(centre, centre, radius, -90, angle - 90, …)` reached `drawArc` as
`startAngle = -157.5f`.

That put the arcs almost anywhere except where their contracts said, in
patterns that looked plausibly like "wrong direction" or "wrong side"
bugs and misled the first two rounds of diagnosis toward angle-convention
and clipping fixes. `Log.i("MobArc", …)` on the raw values showed the
scaling in one line.

## Decision

The `arc` handler unpacks `start_deg` and `end_deg` with a plain
`numberFloat` helper — the same `when (v)` cascade as `canvasFloat`,
without `.dp.toPx()`. `cx`, `cy`, and `r` still use `canvasFloat` because
they are coordinates. `drawArc` is passed straight through:

```kotlin
startAngle = startDeg
sweepAngle = endDeg - startDeg
```

`Mob.Canvas` and Compose's `drawArc` share the same numeric angle
convention (0° right, positive sweep clockwise); no sign flip is
needed once the angles arrive in degrees.

## Consequences

- `MishkaSemiCircleProgress` and `MishkaAngleSlider` render identically
  on iOS and Android for the physical Moto and iPhone I verified.
- `numberFloat` is now the right unpacker for any BEAM-side canvas op
  field that is not a coordinate — degrees, ratios, alpha. Only
  `arc` currently has one; the next non-coordinate field on a new op
  should use it too.
- Pinned by `project_generator_test.exs`. Removing the `numberFloat`
  helper or reverting the `arc` handler to `canvasFloat(op["start_deg"])`
  fails the test.

## `.clipToBounds()` retention

The predecessor ADR (superseded, kept in place) added `.clipToBounds()`
to the Compose Canvas's modifier chain as its fix for the
`MishkaSemiCircleProgress` overdraw. Once the angle bug is fixed the
composite draws in bounds and the clip is no longer required to hide
the specific overdraw that motivated it.

`.clipToBounds()` is retained anyway. SwiftUI's `Canvas` clips its
content to the declared width/height by default; Compose's `Canvas`
does not. Keeping the clip on the Android side gives future
`Mob.Canvas` composites the same "what's outside the box is hidden"
guarantee they already get on iOS — worth the two-line diff
independent of MOB-256. The test asserts both the clip and the
angle handler shape.

## Alternatives considered

- **Keep `canvasFloat` and negate the sweep** (`sweepAngle =
  -(endDeg - startDeg)`). Fixed `MishkaSemiCircleProgress` by
  accident — the scaled angles happened to land back on a semi-circle
  bulging up — and broke `MishkaAngleSlider`, which then showed a
  long arc in the wrong hemisphere. Reviewed against source and
  discarded once the raw log line revealed the actual angle values.
- **Fix at the `Mob.Canvas` layer** by normalising the map before it
  crosses the wire. `start_deg` and `end_deg` are already documented as
  degrees on the BEAM side; the mismatch is a bridge-layer bug and
  belongs to the bridge to fix.

## Related

- MOB-246 (mob_mishka extraction epic) — surfaced this while
  screenshotting both physical devices side by side.
