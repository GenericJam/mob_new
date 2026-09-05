# Synthetic input is dispatched over real time, and a primitive that cannot work is absent

Date: 2026-09-05
Status: accepted
Ticket: MOB-160

## Context

An agent driving a Mob app needs to tap, type and gesture on a real device.
The obvious route, `Instrumentation.sendPointerSync`, needs `INJECT_EVENTS`,
a signature permission no normal app can hold. The route that does work from
inside the app is dispatching `MotionEvent`s and `KeyEvent`s straight at the
activity's decor view, which is what the bridge now does.

Getting the events to the view turned out to be the easy half.

## Decision

### Gestures are dispatched over real elapsed time, never synthesised timestamps

The first implementation built a whole gesture inside one main-thread block:
`ACTION_DOWN`, a loop of `ACTION_MOVE`s, `ACTION_UP`, each carrying a
fabricated future `eventTime`. Every event reached the view, and every gesture
was ignored. A long press registered as a tap and a swipe moved nothing.

Android's gesture recognisers do not read the timestamps we hand them and
conclude that time passed. A long press waits on a posted callback, and
Compose resolves drags and touch slop in a pointer-input coroutine that only
resumes when the main looper is free. A block that runs a gesture to
completion without ever yielding the looper starves exactly the machinery
meant to interpret it.

So gestures suspend between events (`onMainAsync`) and stamp each event with
a real `SystemClock.uptimeMillis()`. Measured on a physical moto g power:
a long press went from never firing to firing, and a swipe from zero movement
to scrolling the full 1033px extent.

Discrete events — a tap, a keystroke — have no duration to get wrong and stay
on the synchronous path.

### `clear_text` ships absent rather than broken

Two implementations were tried on device and both reported success while
failing to clear. Backspacing in a loop is dispatched far faster than the text
field recomposes, so the events coalesce within a frame: roughly four of two
hundred registered. Ctrl+A then delete does not select in a Compose text field
either, and removes a single character.

A method that returns `true` having cleared nothing is worse than no method.
`Mob.Test.capabilities/1` reports an absent method as `clear_text: false`,
which is true, and an agent can plan around a capability it knows it lacks.
It cannot plan around a lie. The primitive stays out until there is a
mechanism that actually works.

## Consequences

- Gesture calls block the caller for the gesture's real duration. A
  `long_press_xy` of 800ms takes 800ms, because there is no other way for it
  to be a long press.
- `on_long_press` fires on the node types that carry gestures (`column`,
  `row`, `text`, `icon`, `box`) and not on `button`, matching iOS. A synthetic
  long press on a `button` correctly does nothing; the target, not the
  injector, is what to change.
- Verification of an input primitive means observing app state change through
  it, not that the call returned `:ok`. Every method here returned `:ok` while
  doing nothing at some point during development.
