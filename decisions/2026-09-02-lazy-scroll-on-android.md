# :scroll can compose only what is on screen, opt-in

- Date: 2026-09-02
- Status: accepted
- Implements: MOB-128, part of MOB-124
- Supersedes: an earlier draft of this record whose central claim was wrong; see "What this record got wrong the first time"

## Context

Measured on a Moto G Power (2021), one render at a time with 2.5 s of quiet between so no frame queues behind another. A 200-row screen cost **141 ms of main-thread work per update** (p50), of which 111 ms was Compose recomposition — while the whole BEAM-plus-NIF pipeline for the same frame was 45 ms. The native rebuild, not the wire, is the dominant cost.

`:scroll` rendered as `Column(...).verticalScroll(...)`, which composes every child regardless of the viewport. A 200-row list composed all 200 rows to show about ten.

## Decision

A vertical `:scroll` renders through `MobLazyList` (`LazyColumn`) **when the author opts in with `lazy: true`** and its content can be lazified. Otherwise it keeps the eager `Column` + `verticalScroll`.

### Why opt-in rather than the default

Laziness is not free of observable consequences, and they are not cosmetic:

- Rows below the fold are never composed, so they never register a frame. `Mob.Test.element_frames` and `tap_id` cannot address them, where the eager column laid out every child on or off screen.
- Scroll position becomes **index**-based rather than pixel-based, changing what `Mob.Test.scroll_info` reports for that node.

`lazy_list` already exists and makes exactly this trade explicitly. Making it the silent default for every `:scroll` would change harness behaviour under apps that never asked for it. So the author asks.

### What flattening may drop, and the guard

Mob screens are written `scroll > column > rows`, so a scroll node usually has exactly one child; lazifying its direct children buys nothing because the column underneath still composes every row. When that column can be removed without changing what the user sees, its children become the items.

The guard is deliberately narrow — the column's own props must all be in `{fill_width, fill_height}`:

- A `LazyColumn` already spans its container's width, and `fill_height` is a no-op under the unbounded main axis a scroll gives its content, so both are genuinely droppable.
- Anything else — padding, background, align, an `id` the harness addresses, a tap handler — is something the column contributes and would be **silently lost**. Those keep the eager path.

A child carrying `weight` also forces the eager path. `weight` comes from `ColumnScope`; `LazyColumn` items have no such scope, so a flattened child's weight would vanish without a trace.

The practical consequence is that the house style `scroll > column padding: ...` does **not** lazify even with `lazy: true` — the author must move those props onto the scroll node. That is a deliberate trade of reach for safety, and widening the set (mapping `padding` to `contentPadding`, `background` to a container modifier) is follow-up work with its own nuances.

### The pixel ScrollState must be unregistered

`scrollInfo` checks `scrollState` **before** `lazyState`. The `rememberScrollState()` above the branch is never attached to a `verticalScroll` on the lazy path, so its `maxValue` keeps its `Int.MAX_VALUE` default. Leaving it registered made `scroll_to(:bottom)` return `:ok` **without moving the list**, and `screenshot_tour` compute roughly a million pages. The lazy path now clears it.

## What this record got wrong the first time

The first version of this change gave a `fill_height` scroll child `Modifier.weight(1f)` from its parent column, justified as: *"`Column` only measures a child against the remaining space when that child is weighted; `fill_height` alone leaves it unbounded."*

**That is false.** An adversarial review disproved it from the shipped `foundation-layout` bytecode: in `RowColumnMeasurementHelper`, a non-weighted child of a bounded `Column` is measured with `mainAxisMax = remaining` — bounded. `weight` only raises `min` to equal `max`.

Worse, the weight actively broke things: inside an *unbounded* Column (a nested scroll) the weighted branch computes `targetSpace = mainAxisMin` = 0, so the child measured at **zero height** and disappeared — and it changed weight distribution for apps that never touched the lazy path.

The blank list that motivated it is now explained by MOB-136: on Android a `text_field` in a row under an unbounded-height container blows the row height to ~500 px, so its siblings are centred off screen. The eager path rendered nothing for the same reason, which a screenshot of the *eager* baseline established only later. The weight hunk was a fix for a misdiagnosis, and it has been removed.

## Results

The cleanest evidence is a single-variable A/B: same build, same screen, same
fixture, toggling only the `lazy: true` prop. 500 rows, Moto G Power,
main-thread frame cost:

| | p50 | max | recompose max |
|---|---|---|---|
| eager | 498.9 ms | 1385.9 ms | 1197.7 ms |
| `lazy: true` | **115.8 ms** | **164.8 ms** | **69.7 ms** |

4.3x on p50 and 8.4x on the worst frame, which is the one a user feels as a
stutter.

An earlier scaling run across two builds, on a lighter fixture, gives the shape:

| rows | eager p50 / max | lazy p50 / max |
|---|---|---|
| 50 | 77.8 / 106.7 ms | 83.2 / 120.4 ms |
| 200 | 140.9 / 162.1 ms | 81.5 / 107.5 ms |
| 500 | 104.0 / 307.9 ms | 91.6 / 110.9 ms |

**Lazy cost is flat in list length** (83/81/92 ms across 50, 200 and 500) while
eager grows. At 500 rows the eager p50 there is unreliable — under backpressure
the app draws less often, so fewer heavy frames are sampled; its `max` is the
honest number, and the same-build A/B above avoids that artefact entirely.

At 50 rows lazy is slightly *worse*. Expected: the list nearly fits on screen, so
there is little to skip and `LazyColumn` has real setup cost. This is a
long-list optimisation, which is another reason it is opt-in.

## What this does NOT do

It does not make Compose skip anything. Skipping is separately broken — a composable with a **literally constant** argument still recomposes every frame in this composition, so `@Immutable` on `MobNode` changed nothing. Laziness works because it reduces how many nodes are composed at all. See MOB-127.

## Verification

Every measurement was taken with a screenshot confirming the rows actually render. An earlier version of this change reported a `RenderNode` count of 24 (from 1617) and a frame of 78 ms (from 312 ms) **while rendering a blank list**. Both the counter and the frame timing looked like a spectacular success. Only pixels caught it.
