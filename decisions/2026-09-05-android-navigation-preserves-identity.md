# Android navigation preserves composition identity

Date: 2026-09-05
Status: accepted
Ticket: MOB-146

## Context

`MainActivity` rendered every screen through
`AnimatedContent(targetState = state, contentKey = { it.navKey })`.
`AnimatedContent` wraps each content in `key(contentKey)`, so a changing key
disposes the outgoing composition and builds the incoming one from nothing —
structurally the same thing `.id(currentNavVersion)` did on iOS before
MOB-129.

Measured on a 1600-node screen, physical moto g power, using the frame timing
added earlier in this ticket:

| transition | p50 |
| --- | --- |
| `none` | 221ms |
| `push` | 818ms |
| `pop` | 788ms |

A navigation cost roughly four times a re-render of the same tree, and the
whole difference was the identity change.

## Decision

One mount point at a fixed structural position. That position is its identity;
no key is used. A navigation replaces the tree inside it instead of disposing
the composition and building a new one.

Note what this does **not** do. It does not make navigation "just a re-render
of a different tree". Nothing in a Mob screen can be skipped — `MobNode` holds
a `Map` and a `List`, so Compose infers it unstable, and this toolchain
(Kotlin 1.9.22, Compose compiler 1.5.8) has no strong skipping — so every
recomposition walks all 1600 nodes either way. What is saved is the dispose
and the slot-table teardown and rebuild, not the node building. That is why
navigation still costs about three times a re-render after this change, as it
did before it. Making the rest of the gap available is MOB-162.

The slide is driven by an animated offset on that mount point rather than by
an enter/exit transition, because those only fire on insert/remove and
insert/remove is precisely what cost the time.

Baseline and fix re-measured back to back in one session, same device, same
build of everything else, n=20/10/10:

| transition | before | after | |
| --- | --- | --- | --- |
| `none` | 227ms | **128ms** | 44% faster |
| `push` | 794ms | **374ms** | 53% faster |
| `pop` | 784ms | **440ms** | 44% faster |

`none` improves as well, because `AnimatedContent`'s machinery is gone rather
than merely bypassed.

**An earlier draft of this record claimed navigation had dropped to ~160ms and
now cost the same as a re-render. That was a measurement artifact and the
claim was wrong.** In the version those numbers came from, the tree was
installed by a `LaunchedEffect`, which runs *after* composition — so the frame
`native_stats` measured still showed the OLD tree, and the build of the new
one happened outside the bracket. Rendering straight from `state` fixed both
the artifact and a blank-screen bug. The lesson is worth keeping: when an
instrument reports a number better than the theory allows — navigation cheaper
than a re-render of the same tree — the instrument is the thing to doubt.

### One mount point, not iOS's two

iOS keeps two slots and parks the outgoing tree, which buys depth-1 retention:
popping back diffs against the screen still sitting in the other slot. That
was implemented here first and then removed, because it does not transfer.

A parked Compose subtree recomposes on every render of the active screen —
measured directly by logging recompositions, 6 of the parked node across 6
re-renders — which took a steady-state re-render from 151ms to 273ms.
Re-renders are far more frequent than navigations, so retention was paying
122ms on the common path to save on the rare one.

Three attempts to make it skip failed, and none of them could have worked:
`MobNode` is unstable and this toolchain has no strong skipping, so nothing in
that subtree has a reachable skip path at all. Hoisting the `Animatable` out
of the parameters, removing an early `return`, and wrapping the tree in an
`@Immutable` holder each addressed something other than the actual unstable
parameter. Retention becomes worth revisiting once that is fixed, which is
MOB-162.

### The visible trade

The outgoing screen no longer slides out simultaneously; the incoming one
slides in over the container background, which is now painted explicitly from
`MaterialTheme.colorScheme.background` — the window background underneath is
hardcoded black, so a light-themed app would otherwise get a black wedge
sweeping across it for the whole slide.

Two smaller losses, both from dropping the enter/exit transitions: a `reset`
no longer cross-fades (it was `fadeIn`/`fadeOut` over 250ms, and `reset` is
the default for `Mob.Socket.reset_to/4`), and a push no longer parallaxes the
outgoing screen at a third of the distance.

`Mob.Socket`'s docs and `guides/navigation.md` in the `mob` repo still promise
a reset cross-fade, and iOS still does one. That is a new platform divergence
in public API docs which cannot be fixed from this repo; MOB-165 tracks it.

## What preserving the composition means for per-widget state

Disposal used to reset everything a screen remembered. It no longer does, and
that is a wider behavioural change than the animation losses above.

Anything held in a `remember` whose key does not move across a navigation now
survives one, if the new tree puts a widget in the same composition slot.
Everywhere that would be wrong, the slot epoch is now part of the key:

- a lazy list's `LazyListState` and a `:scroll` view's `ScrollState`, which
  would otherwise open the new screen at the old one's offset. `setRootJson`
  clears `lazyListStates` on navigation and says why, and that clear had
  quietly stopped working: the map entry went, the remembered object stayed.
- a `text_field`'s local text and a `slider`'s thumb, keyed on the incoming
  `value` prop alone, which re-seeds only when the value DIFFERS — and two
  screens whose field is empty is the common case.
- a sheet's presentation state, where an id-less sheet dismissed on the way
  out would arrive already dismissed and never show again.

One retention is deliberate and left alone: **focus and the keyboard.** The
old `RootState` docs guaranteed that a same-screen re-render would not drop
focus or dismiss the IME; that guarantee now extends across a navigation into
a screen with a field in the same slot. Resetting it would need a signal for
"this is a different screen" that is finer than the epoch, and keeping typing
alive across a re-render that happens to coincide with a navigation is more
often right than wrong. Recorded because it is a real change, not because it
is settled. Showing both at once requires both to be
mounted, which is the retention that costs more than it saves.

### Every navigation re-keys the frame trackers

The frame-registry generation gate has each tracked node remember the
generation current when it first composed, and refuses writes stamped older
than the current one. That used to work for free: `AnimatedContent` made the
incoming tree a fresh composition, so it always captured the bumped value.

With the mount point preserved it is not free. Nodes Compose reuses across a
navigation keep the generation they captured for the previous screen, which
`setRootJson` has just superseded, and their frame writes would be refused for
ever — `element_frames` silently losing those ids and `tap_id` no longer
finding them, with nothing raised anywhere.

So the capture is keyed on an epoch provided through `LocalSlotEpoch`, and
`navKey` is that epoch: it already moves on every non-`"none"` transition and
nothing else, which is exactly when the trackers must re-capture. A
same-screen re-render leaves it alone; re-keying on every render would
re-capture constantly and leave the gate as dead code that still looked like a
fix. Verified on device across five consecutive navigations, with the tracked
element located every time.

Providing it through a `CompositionLocal` rather than having trackers read the
root state is what keeps every tagged node from resubscribing to every root
update.

## The bug this went through on the way

The first working version drove the animation from `LaunchedEffect(state)`.
`LaunchedEffect` cancels its coroutine when the key changes, and `state` is a
new `RootState` on every render — so any re-render arriving during the 300ms
slide cancelled `animateTo` and left the offset frozen off-canvas. **The app
rendered blank.**

It is worth recording because of how it failed, not that it failed. The BEAM
went on reporting the correct screen and the correct assigns throughout, so
every probe an agent has — `screen/1`, `assigns/1`, `element_frames/1` — said
the app was fine while the device showed black. It was found by sending one
re-render 100ms after a navigation and taking a screenshot; nothing short of
looking at the pixels would have caught it.

The animation is now keyed on `navKey`, so an ordinary re-render cannot cancel
it and a second navigation correctly interrupts and restarts it. The
zero-distance branch also snaps the offset back to rest, so an interrupted
slide cannot leave the screen displaced.
