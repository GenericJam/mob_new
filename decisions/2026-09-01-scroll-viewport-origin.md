# Expose the scroll viewport's unclipped window origin on ScrollHandle

- Date: 2026-09-01
- Status: accepted

## Context

A downstream app's section-jump bar needs a browser-style anchor jump: land
the target section's top edge at the top of the scroll viewport, clamped at
the end of content. Compose's `BringIntoViewRequester` cannot express that —
it scrolls *minimally*, moving whichever edge is nearest just inside the
viewport, so a target below the fold parks at the bottom edge and the heading
after it stays off-screen.

Getting the exact destination means converting the target's window position
into an offset in the scroller's content. The plugin can read its own marker
position, and `MobBridge.scrollHandle(id)` already hands out the `ScrollState`.
The missing piece was the viewport's own origin.

Rejected alternatives:

- **Pass a taller rect to `bringIntoView(rect)`.** Compose's
  `relocationDistance` picks whichever edge moves least, so top-alignment only
  falls out when the requested rect height happens to equal the viewport
  height, and a very tall rect makes upward jumps a silent no-op (the
  `leadingEdge < 0 && trailingEdge > containerSize` branch returns `0f`).
- **Reuse the element frame registry.** `recordElementFrame` stores
  `boundsInWindow()`, which is clipped. Every downward jump starts with the
  target out of view, where those bounds are empty — the conversion would
  silently yield garbage.
- **A full `Mob.UI.scroll_to_element/2` primitive in mob.** The right long-term
  layering, but it spans mob's Elixir API plus both native renderers and a mob
  release; too much for a bug fix that one field unblocks.

## Decision

`MobBridge.ScrollHandle` carries `viewportOriginXPx` / `viewportOriginYPx`,
recorded via `positionInWindow()` in the `"scroll"` branch's existing
`onGloballyPositioned` — beside `viewportPx`, which is already there for the
same "ScrollState doesn't expose it" reason.

## Consequences

- Any plugin can now convert a descendant's `positionInWindow()` into a content
  offset: `content = descendantWindow - viewportOrigin + scrollState.value`.
- Two floats written per layout pass on scroll nodes that have an `:id`; the
  same `onGloballyPositioned` already ran, so there is no new layout work.
- iOS needs nothing: the equivalent marker registry there walks up to the
  enclosing `UIScrollView` and already top-aligns with a clamp.
- Shells generated from an older mob_new lack the field. A consumer that binds
  to `MobBridge` reflectively should degrade to the old minimal scroll rather
  than crash — which makes the regression silent, so downstream apps want a
  post-regeneration check for the field.
