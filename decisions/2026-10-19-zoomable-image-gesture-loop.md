# Zoomable image: one gesture loop, no consumed downs, 4096 px decode
- Date: 2026-10-19
- Status: accepted

## Context

mob 0.9.24 adds `zoomable: true` on `:image` (see mob's
`decisions/2026-10-19-zoomable-image-is-native.md`). `MobImage` in
`MobBridge.kt.eex` carries the Android half.

## Decision

- Pinch, pan and double tap share one `pointerInput` loop on the image,
  placed before its `graphicsLayer` (so positions are untransformed) and after
  `clipToBounds()` (so the zoomed layer is clipped to the frame).
- Double tap is detected in that loop, not with `detectTapGestures`:
  `detectTapGestures` consumes every down, and `RenderNodeInner` puts an
  image's `on_tap` in a `clickable` outside this node, which then never fires.
  The loop consumes nothing but movement, and movement only past touch slop
  and, for one finger, only while zoomed in. That keeps taps for the
  clickable and one-finger drags at 1x for a parent scroll or pager.
- The zoomable path requests the picture at up to 4096 px on its long side
  with `Precision.INEXACT` (never upscaled). Coil's default sizes the bitmap
  to the frame, which turns a 4x zoom into a magnified screen-sized bitmap;
  4096 x 4096 ARGB stays under the 100 MB a Canvas will draw.

## Consequences

- An `on_tap` on a zoomable image fires for each tap of a double tap.
- Apps carrying an older generated `MobBridge.kt` must copy `MobImage`,
  `MobZoomableImage` and the new imports by hand (CHANGELOG "Upgrading").
