# Fixed dimensions wrap fill constraints
- Date: 2026-09-13
- Status: accepted

## Context

The generated Android bridge appended `width` and `height` after
`fillMaxWidth` and `fillMaxHeight`. A 306dp-wide, full-height `Column` with a
weighted vertical scroll then produced `fillMaxHeight().width(306.dp)`. That
screen was reported to enter Compose measurement/recomposition until the
process exhausted its heap. Wrapping the dimensions and fills in separate
containers avoided the failure and isolated the generated constraint chain as
the remaining suspect to verify with the unwrapped tree on-device.

Compose modifiers are nested measurement wrappers in declaration order, so
this order is part of Mob's layout contract even when two modifiers act on
different axes.

## Decision

Generated Android bridges apply fixed `width` and `height` before fill
modifiers. A fixed dimension suppresses fill on the same axis; a fill on the
other axis remains active. The resulting fixed-width/full-height chain is
`width(...).fillMaxHeight()`. This completes the parity follow-up deferred by
`mob/decisions/2026-09-11-column-row-fixed-dims-precedence.md` for valid,
positive dimensions.

## Consequences

- Fixed dimensions now win over same-axis fills on both Android and iOS.
- A fixed-width column can own a weighted scrolling body without an extra box
  used solely to split the constraints.
- Existing apps must regenerate or copy the bridge change before they benefit;
  updating only the `mob` dependency does not replace app-owned Kotlin.

## Verification

The unwrapped Crosscourt drawer was rebuilt with this modifier chain and run on
a physical Moto G Power (2021). Its 306dp-wide, full-height `Column` rendered
with the weighted scroll and pinned footer, survived repeated scroll gestures,
and remained alive after the observation period. Java heap allocation remained
stable at roughly 5.4MB and logcat contained no `OutOfMemoryError` or fatal
exception.
