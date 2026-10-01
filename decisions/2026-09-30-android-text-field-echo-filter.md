# Android text fields ignore echoes of their own edits
- Date: 2026-09-30
- Status: accepted
- Issue: MOB-309

## Context
`MobTextField` resynced to the pushed `value` on every render epoch whenever
it disagreed with the field. Each keystroke sends an on_change, and the render
it triggers carries the value as of that keystroke. During fast typing the
field is already further on, so each render rewound it to a stale prefix: the
keystrokes in between were lost, and the caret, coerced into the shorter
text, put later ones in the wrong place. On an emulator, `adb shell input text`
of a 46-character string into `value={@draft}` arrived as
`abcdefgijklmnopqrstuwxyz0123456789ABCDEFGHIJvh`.

The same comparison wiped fields with no `value` prop: `incoming` defaulted to
`""`, so any re-render of the screen erased what had been typed. Typing
`hello` into such a field left it empty and the BEAM holding `"o"`.

## Decision
`MobTextSync` keeps the values the field sent and has not seen come back. A
render carrying one of them is an echo: the field keeps its text and forgets
that entry and every older one, since the BEAM handles change events in order.
Any other value is the BEAM's own (a clamp, a transform, a reset after submit),
so the field adopts it, puts the caret at the end, and forgets the queue: the
edits still in flight were made against text that has just been replaced.

A field with no `value` prop is uncontrolled and ignores renders. Its state is
keyed on `LocalSlotEpoch`, so a navigation still resets it (MOB-146).

## Alternatives rejected
- **iOS's guard, "never adopt while focused".** It also ignores a clamp or a
  reset while the user is typing, which the render-epoch resync was added to
  support on Android.
- **An edit counter in the protocol** (React Native's `mostRecentEventCount`).
  Exact, but needs the BEAM to return the count with the value, which is a
  change to mob's change-event contract, not a renderer fix.

## Residual
Without an acknowledgement from the BEAM, a pushed value that equals an
entry in the queue is indistinguishable from an echo of it. Three cases follow:

- A transform that disagrees with every sent value is adopted even if the
  user has typed past it. A field that upcases its input can still lose
  keystrokes in a burst, as it did before this change.
- Coalesced renders can hide a rejection. Sent `1234`, `12345`, `123456`; the
  screen clamps to five; the sender drops the earlier frames and pushes
  `12345` once. That matches the second entry, so the field keeps `123456`
  until the next render that is not an echo. A rejection that leaves the
  tree unchanged was already invisible before this change, because an
  unchanged tree is not repainted at all. A hard limit belongs in
  `max_length`, which rejects the keystroke in the field.
- Duplicates: after `a`, `ab`, `a` with only the last `a` pushed, `ab` stays
  queued, so a later `ab` the BEAM sets on its own is taken for an echo once.
  `lastIndexOf` would trade that for undoing a backspace in the common,
  uncoalesced sequence, which is worse.

All three self-correct at the next push that is not an echo. Only an edit
counter returned with the value closes them.
