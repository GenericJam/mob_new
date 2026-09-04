# Android element frames: gate writes on a nav generation

- Date: 2026-09-03
- Status: accepted
- Mirrors: mob's `decisions/2026-08-27-frame-registry-liveness.md` (iOS,
  MOB-102 / MOB-103)

## Context

`MobBridge.setRootJson` clears `elementFramesById` on any non-`"none"`
transition, but the write path had no gate at all: `recordElementFrame` stored
whatever `onGloballyPositioned` handed it.

`MainActivity` renders the tree inside `AnimatedContent(contentKey = { it.navKey })`,
and `AnimatedContent` keeps the outgoing composition mounted for the whole exit
animation. `push` and `pop` slide that screen out, so every node in it is
re-laid-out on each display frame the entire way, firing `onGloballyPositioned`
long after the clear ran. The leaving screen therefore refilled the registry
with mid-animation coordinates, and `Mob.Test.element_frames` / `tap_id` then
reported and tapped positions belonging to a screen the user was no longer
looking at. Same bug iOS had, same shape.

## Decision

A tracker captures the nav generation current when it first composes and stamps
every write with it; `recordElementFrame` refuses a write stamped older than
the current generation. Three sub-decisions are worth recording.

**A private `AtomicLong`, not `navKey`.** `navKey` moves on exactly the right
events, which makes reusing it tempting. It is rejected for two reasons. It
lives inside `_rootState`, a Compose snapshot state, so a tracker reading it
would subscribe every tagged node to root updates, and the outgoing tree
recomposing during its own exit animation would read the *incoming* `navKey`
and restamp itself: precisely the write the gate exists to refuse. It is also
the `AnimatedContent` `contentKey`, a statement about animation identity that
is free to be reset, reused, or replaced by a screen name if the transition
mechanism changes, whereas the gate needs a value that only ever increases.
`AtomicLong` rather than a plain `Long` because the bump runs on the NIF/binder
thread while the capture and the check run on the Compose main thread; each
access is a single atomic one and no lock is added that would have to be
ordered against `elementFramesById`.

**`remember(id)`, not a keyless `remember` and not a per-recomposition read.**
Reading the counter inside `onGloballyPositioned`, or keying the `remember` on
the counter itself, would make a write incapable of ever being stale: the gate
would be dead code that still read as a fix. Keying on `id` re-runs the capture
exactly when the modifier starts tracking a different element, which is the one
way a live composition can hold a generation that was never its own. Only
`column`, `row` and the lazy list key their children on the author's `:id` via
`mobChildKeys`; everywhere else children occupy positional composition slots,
so a slot can be handed a different node, and a different `:id`, while keeping
its remembered state. Navigation itself is covered without any key, since the
incoming tree is a fresh composition, but keying on `id` keeps the gate from
resting entirely on that one `AnimatedContent` internal.

**The bump goes first, ahead of the clears.** Both run on the NIF thread while
Compose may be midway through a layout pass, so an outgoing write landing
between a clear and a later bump would be accepted and would survive as a stale
entry. Bumping first leaves no such window, and it necessarily precedes the
`_rootState` write, which is what schedules composition of the incoming tree.

## Consequences

- `recordElementFrame` takes a `generation: Long` and `frameTrackingModifier`
  is now `@Composable`. Both are `MobBridge` members with a single call site in
  `RenderNodeInner`, so nothing outside this template moves.
- Ordering verified by reading, not on a device. `nif_set_root`
  (`mob/android/jni/mob_nif.zig`) calls `setRootJson` synchronously on the BEAM
  dirty-CPU scheduler thread, so the bump, the clears and the `_rootState`
  write happen in program order on one thread before Compose is scheduled.
  `javap -c` on `androidx.compose.animation.AnimatedContentKt` confirms
  `AnimatedContent` invokes `contentKey` per visible state and passes the
  result to `Composer.startMovableGroup`, then looks the content lambda up by
  that same key: a changed `navKey` is a new movable group, so the incoming
  tree recomposes from scratch and captures the bumped value, while the
  outgoing content is re-invoked with its own stored state and therefore its
  own unchanged ids, so its `remember(id)` does not re-run.
- Not device-verified. The Android equivalent of iOS's `.onDisappear`
  compare-and-delete liveness signal is also still missing, so the divergences
  the iOS decision record calls out (a lazy row scrolled out of range, an
  inactive tab, a dismissed sheet, all keeping a last-known frame forever)
  remain open on Android. This change fixes the navigation case only.
