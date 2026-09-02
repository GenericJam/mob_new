# :scroll composes only what is on screen (Android)

- Date: 2026-09-02
- Status: accepted
- Implements: MOB-128, part of MOB-124
- Companion: `mob/decisions/2026-09-01-render-instrumentation.md`

## Context

Measured on a Moto G Power (2021), one render at a time with 2.5 s of quiet
between so no frame queues behind another. A 200-row screen cost **134 ms of
main-thread work per update**, of which 107 ms was Compose recomposition — while
the entire BEAM-plus-NIF pipeline for the same frame was 45 ms. The native
rebuild, not the wire, is the dominant cost.

`:scroll` rendered as `Column(...).verticalScroll(...)`, which composes every
child regardless of the viewport. A 200-row list composed all 200 rows to show
about ten.

## Decision

Vertical `:scroll` renders through `MobLazyList` (`LazyColumn`) when its content
can be lazified, and keeps the eager `Column` + `verticalScroll` otherwise.

Two things had to be solved, and both are the actual content of this decision.

**Flattening.** Mob screens are written `scroll > column > rows`, so a scroll
node usually has exactly ONE child. Lazifying its direct children buys nothing —
the column underneath still composes every row. So when the sole child is a
column whose own props are layout-neutral, its children become the items.

Only `fill_width` and `fill_height` count as neutral: a `LazyColumn` already
spans its container's width and takes its height from the scroll node. Anything
else — padding, background, align, an `id` the test harness addresses — changes
what the user sees and would be silently dropped, so those keep the eager path.

**Bounded height.** A lazy container must be measured with a bounded main axis.
`Column` only measures a child against the remaining space when that child is
weighted; `fill_height` alone leaves it unbounded. `verticalScroll` tolerates
that, `LazyColumn` does not — it composes zero items and renders an **empty
screen**. So a `fill_height` scroll child now gets `Modifier.weight(1f)` from its
parent column.

`MobLazyList` is reused rather than a fresh `LazyColumn` so `:scroll` inherits
the list-state hoisting already there: `rememberLazyListState` resets to 0 on
every BEAM re-render, and that code keys state off the node's handle instead.

## Results

Main-thread frame cost, same device, same screens:

| rows | eager p50 | eager max | lazy p50 | lazy max |
|---|---|---|---|---|
| 50 | 77.8 ms | 106.7 ms | 83.2 ms | 120.4 ms |
| 200 | 140.9 ms | 162.1 ms | 81.5 ms | 107.5 ms |
| 500 | 104.0 ms | 307.9 ms | 91.6 ms | 110.9 ms |

The property that matters is not the headline percentage but the shape: **lazy
cost is flat in list length** (83, 81, 92 ms across 50, 200 and 500 rows) while
eager grows. At 500 rows the eager p50 is unreliable — under backpressure the
app draws less often, so fewer heavy frames are sampled; its `max` of 308 ms is
the honest number there, against 111 ms lazy.

At 50 rows lazy is slightly *worse*. That is expected: the list nearly fits on
screen, so there is little to skip and `LazyColumn` has real setup cost. This
change helps long lists and is neutral-to-slightly-negative on short ones.

## What this does NOT do

It does not make Compose skip anything. Skipping is separately broken — a
composable with a **literally constant** argument still recomposes every frame in
this composition, so `@Immutable` on `MobNode` changed nothing. Laziness works
because it reduces how many nodes are composed at all, not because unchanged
ones are reused. See MOB-127.

## Verification

Every measurement here was taken with a screenshot confirming the rows actually
render. That is not ceremony: an earlier version of this change reported a
`RenderNode` count of 24 (from 1617) and a frame of 78 ms (from 312 ms) **while
rendering a blank list**, because the lazy container was measured unbounded. Both
the counter and the frame timing looked like a spectacular success. Only pixels
caught it.
