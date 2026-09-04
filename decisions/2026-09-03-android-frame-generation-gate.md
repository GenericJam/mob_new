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

**One monitor covers the counter and the registry.** The first version of this
used an `AtomicLong` beside the untouched `ConcurrentHashMap`, on the reasoning
that each access is then individually atomic and no lock has to be ordered
against the map. That is not enough, and the version of this document that
shipped with it claimed a soundness property the code did not have.

`recordElementFrame` is a check-then-act across two objects. With only an atomic
counter, a tracker can read a generation that is still current, lose the thread,
and have `setRootJson` bump and clear before its write lands:

    Compose thread:  read generation -> 1     (gate passes)
    NIF thread:                                bump -> 2
    NIF thread:                                clear()
    Compose thread:  map[id] = frame           <- stale entry survives

`ConcurrentHashMap.clear()` is not atomic against a concurrent `put` either.
Ordering the bump ahead of the clear narrows the window from "clear-to-bump plus
read-to-write" down to "read-to-write"; it does not close it. Holding one lock
across the check and the write, and across the bump and the clear, does.

This is what iOS does and the reason it does not have the hole:
`mob_register_frame` performs the generation check and the dictionary write
inside `@synchronized(reg)`, and the bump takes the same monitor. The lock is
uncontended, taken once per tracked element per layout pass, on a monitor
nothing else wants.

The bump still precedes the `_rootState` write, which is what schedules
composition of the incoming tree, and that ordering is what makes the incoming
trackers capture the new value.

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
- Not device-verified. The premise that a screen sliding out under
  `AnimatedContent` keeps firing `onGloballyPositioned` the whole way is read
  off the animation's placement behaviour rather than measured, and it is worth
  one device pass, because the fix is otherwise hard to falsify.
- **This is one of iOS's three parts, not all of them.** iOS pairs the
  generation gate with a purge keyed on the live id set, run on *every*
  `set_root` including `"none"`, and an `.onDisappear` compare-and-delete keyed
  on a write sequence number. Android has neither, so two cases stay broken and
  are not addressed here:
  - a same-screen re-render (`transition: "none"`, the default for in-screen
    updates) that drops an `:id` from the tree leaves that element's last frame
    in the registry for ever, and `tap_id` then taps whatever now occupies
    those coordinates;
  - a lazy row scrolled out of range, an inactive tab, or a dismissed sheet
    keeps its last-known frame, exactly as the iOS decision record describes.
- `scrollHandlesById` has the same stale-repopulation shape and is cleared in
  the same block, ungated. `MobBridge.scrollHandle(id)` mutates handle fields
  from composable bodies, including the outgoing screen's recompositions after
  the clear. In practice `AnimatedContent` composes the outgoing content before
  the incoming one, so the incoming write lands last and it is usually benign,
  which is why it is recorded here rather than fixed alongside.
- `lazyListStates` is a plain `mutableMapOf` mutated from the Compose thread and
  cleared from the NIF thread. Pre-existing rather than introduced here, but the
  changelog's claim that the bridge registries are thread-safe does not hold for
  that one.
