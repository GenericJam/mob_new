# clip_width / clip_height: a draw-time clipRect at the head of nodeModifier
- Date: 2026-11-20
- Status: accepted

## Context

mob adds `clip_width` / `clip_height` on every node (MOB-536): the fraction f
of the node's own laid-out width / height that stays visible. Each cuts at one
line: `clip_width` at the leading edge + f × width (leading = left in LTR, right
in RTL), `clip_height` at the top + f × height; everything on the kept side of
the line stays, including what the node draws past its own bounds. iOS borders
are centred strokes, so a band bounded at the node's leading edge would halve
the leading border. `MishkaRating` draws its half star with them: a filled glyph
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
- Every side but the cut line is `±MOB_CLIP_UNBOUNDED` (1e6 px), not the
  node's bounds, so whatever the node draws past them there stays visible, as
  on iOS. Finite on purpose: `Float.MAX_VALUE` times a layer scale overflows to
  infinity in the canvas transform.
- `native_view` never gets `nodeModifier` (registry factories take no
  modifier), so `RenderNodeInner` wraps it in
  `Box(mobFractionClip(...), propagateMinConstraints = true)`, only when a prop
  is set; an unclipped native view lays out exactly as before.
- RTL is read from the `DrawScope`'s `layoutDirection`, which Compose fills
  from `LocalLayoutDirection` for the node. `nodeModifier` is not
  `@Composable` and cannot read the local itself.

## Consequences

- The `clickable` ripple sits before `nodeModifier` in `RenderNodeInner`'s
  chain, so a tappable clipped node ripples over its full frame, as a
  `corner_radius` node already ripples past its rounded corners.
- Apps carrying an older generated `MobBridge.kt` ignore both props on Android
  until they copy the helper (CHANGELOG "Upgrading").
- Not cut: a `sheet`'s ModalBottomSheet container (only the content gets
  `nodeModifier`; when the content scrolls, the clip sits inside the scroll, so
  f is of the content's height and the cut scrolls with it), an `anchored`
  panel (drawn in a separate Popup window) and a `gpu_view`'s GLSurfaceView
  (SurfaceFlinger composites it outside the Compose canvas; the clip only
  limits the hole punched for it).
- On a `button`, the clipped frame is M3's 48dp minimum touch target, the same
  frame a `background` on a button paints, not the 40dp pill centred in it.