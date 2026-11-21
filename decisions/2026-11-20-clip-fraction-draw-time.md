# clip_width / clip_height: a draw-time clipRect at the head of nodeModifier
- Date: 2026-11-20
- Status: accepted

## Context

mob adds `clip_width` / `clip_height` on every node (MOB-536): the fraction of
the node's own laid-out width / height that stays visible, the leading part of
the width (left in LTR, right in RTL) and the top of the height, each cutting
only its own axis. `MishkaRating` draws its half star with them: a filled glyph
over an empty one, the filled one clipped to half its width. `MobBridge.kt.eex`
carries the Android half.

## Decision

- `mobFractionClip(props)` returns a `Modifier.drawWithContent` that wraps
  `drawContent()` in a `clipRect`, and `nodeModifier` starts its chain with it.
  At the head of the chain the content it wraps is the node's background,
  border, `corner_radius` clip and children, and its `size` is the one the
  background is drawn at. Android's RatingBar `ClipDrawable` uses the same
  technique.
- Draw-time, not a size or layout modifier, so the node measures and places at
  full size and its parent and siblings do not move.
- Not `Modifier.clip(shape)`: that is a `graphicsLayer` with `clip = true`,
  an extra layer per clipped node, and a clipping layer also cuts pointer hit
  testing. The contract says hit testing is unchanged.
- The uncut axis is bounded by `±MOB_CLIP_UNBOUNDED` (1e6 px) instead of the
  node's bounds, so a child overflowing on that axis stays visible, as on iOS.
  Finite on purpose: `Float.MAX_VALUE` times a layer scale overflows to
  infinity in the canvas transform.
- RTL is read from the `DrawScope`'s `layoutDirection`, which Compose fills
  from `LocalLayoutDirection` for the node. `nodeModifier` is not
  `@Composable` and cannot read the local itself.

## Consequences

- The `clickable` ripple sits before `nodeModifier` in `RenderNodeInner`'s
  chain, so a tappable clipped node ripples over its full frame, as a
  `corner_radius` node already ripples past its rounded corners.
- Apps carrying an older generated `MobBridge.kt` ignore both props on Android
  until they copy the helper (CHANGELOG "Upgrading").
