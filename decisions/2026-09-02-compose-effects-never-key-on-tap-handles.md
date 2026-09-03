# Compose effects and gesture detectors never key on tap handles

- Date: 2026-09-02
- Status: accepted
- Implements: MOB-138, part of MOB-124
- Builds on: `2026-09-02-lazy-scroll-on-android.md`

## Context

MOB-138 wired 14 event handlers that had a native sender and no Kotlin caller.
Several of them are stateful in a way `on_tap` never was: the scroll family has
to know whether a scroll is already open, whether the threshold has already been
crossed, and what the previous offset was; `on_drag` has to hold a gesture open
across many samples.

The obvious Compose idiom is to key the effect on the values it depends on:

```kotlin
LaunchedEffect(scrollState, scrollH, beganH, endedH, settledH, topH, pastH) { ... }
sized.pointerInput(dragHandle) { ... }
```

That is wrong here, and wrong in a way that produces plausible-looking output
rather than an error.

Handles are not stable. Every render calls `clear_taps` and re-registers each
handler, so the integer for a given prop differs frame to frame. A handler that
updates the screen therefore changes its own keys: event → re-render →
re-register → new key → Compose cancels and restarts the effect.

Measured, one swipe on a scroll node carrying the whole family:

```
110 scroll        every sample phase :began, dx/dy/velocity 0.0, seq 0
108 scroll_began  should be 1
100 scrolled_past should be 1, latched
  0 scroll_ended / scroll_settled
```

Each restart reset `hasBegun`, `last` and `wasPast`. `began` fired forever, the
latch never latched, and every delta was measured against a baseline that had
just been reset to the current value, so it was always 0.

`on_drag` failed differently and worse. It emits continuously, so its own
messages caused the re-render that changed its `pointerInput` key, cancelling
the gesture coroutine one sample in: `began`, a single `dragging`, then
`onDragEnd` never ran and the drag never closed.

Swipe passed its tests throughout. It emits nothing until `onDragEnd`, so
nothing re-renders mid-gesture and the coroutine survives — by accident, and
only until a screen updates for some unrelated reason during a swipe.

## Decision

Key these effects on values that survive a render, and read handles through a
snapshot:

```kotlin
val h by rememberUpdatedState(MobScrollHandlers(scrollH, beganH, ...))
LaunchedEffect(scrollState, horizontal) { ... h.began?.let { ... } ... }
```

`ScrollState` comes from `rememberScrollState()` and is stable; gesture
detectors key on `Unit`. `rememberUpdatedState` gives the effect the current
handle on every emission without restarting it. The emitter re-reads the live
handle each time (`val h = liveDragHandle ?: return`) rather than using the one
captured when the gesture began, which by then may name a recycled slot.

## Consequences

The scroll family and canvas drag behave as iOS documents them. Same swipe after
the change: 1 began, 1 ended, 1 settled, 1 scrolled_past, 14 scroll, with real
deltas and velocities; canvas drag 1 began, 26 dragging, 1 ended.

This is a rule for the bridge, not a local fix: **any** Compose effect that
accumulates state across frames must not take a handle as a key. The guard test
`android_gesture_wiring_test.exs` asserts no `pointerInput(...)` or
`LaunchedEffect(...)` names a handle variable.

The same exposure exists one layer down and is **not** fixed here. `clear_taps`
zeroes the per-handle native throttle state every frame:

```zig
h.throttle_ms = 0; h.delta_threshold = 0;
h.last_emit_ns = 0; h.last_x = 0; h.last_y = 0; h.seq = 0;
```

`throttleCheck` returns unthrottled whenever `last_emit_ns == 0`, so a
high-frequency event whose handler re-renders defeats its own rate limit in the
same feedback loop. The `seq: 0` on all 110 events above is the fingerprint.
Fixing that means giving handles identity across renders, which is MOB-124's
subject, so it is recorded on the issue rather than worked around in Kotlin.
