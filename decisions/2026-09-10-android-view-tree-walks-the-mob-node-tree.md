# Android view_tree walks the Mob node tree, not the View tree

Date: 2026-09-10
Status: accepted
Ticket: MOB-157 (unblocker)

## Context

`Mob.Test.view_tree/1` on Android returned `{:error, :not_loaded}` because
`MobBridge.uiViewTree()` did not exist. The NIF (`android/jni/mob_nif.zig`
`nif_ui_view_tree`) has always been wired for the round trip — `cacheOptional`
looks the method up, and `Mob.Test.view_tree/1` on the BEAM decodes the JSON —
but the Kotlin half was missing. That blocked MOB-157: the differential
iOS/Android detector needs a comparable semantic tree from both platforms.

## What is available on the platform

Two candidates for "the tree the app is currently showing":

**The Android `View` tree.** `activity.window.decorView` and recurse `ViewGroup`.
Rich for classic Android apps and useless for us: a Mob app rendered through
Compose does not create per-composable `View`s. Below `AndroidComposeView`
Compose draws directly, so the walk stops there.

**Compose's `SemanticsOwner`.** The right shape (nodes with `text`,
`contentDescription`, `boundsInWindow`) and the closest thing on Android to
walking iOS accessibility elements. Requires reaching into
`androidx.compose.ui.platform`, which is Compose UI's app-facing package but
whose `SemanticsOwner` accessor moved around Compose versions.

**A third option that turned out to be the right one.** Mob already owns the
tree. `MobBridge._rootState.value.node` is the current `MobNode` — the same
`{type, props, children}` structure `Mob.Test.tree/1` returns. It is
platform-independent by construction, so a differential detector comparing "the
tree Mob decided to render" to "the tree Mob decided to render" is comparing
things designed to match, on the framework's own vocabulary.

## Decision

`MobBridge.uiViewTree()` walks `_rootState.value.node` and returns JSON matching
the shape `Mob.Test.normalize_view_tree/1` already decodes on both platforms:
`{type, class, label, value, frame, bg_color, text_color, children}`.

`label` is lifted from `props["text"]`, falling back to the first Text child's
text — the pattern MOB screens actually build labels with. `value` from
`props["value"]` or `props["placeholder"]`.

`frame` is populated **only for nodes carrying `props["id"]`**, because those are
the ones `Modifier.onGloballyPositioned` already tracks into `elementFramesById`.
iOS reads a frame off every rendered `UIView`; the Compose equivalent has no
per-composable View to hang a `getGlobalVisibleRect` off, so requiring frames on
every node would force id assignments onto every fixture — mixing coverage with
reachability. The comparator picks that up: id'd nodes compare geometry, the
rest do not, and the fixture author chooses.

`class`, `bg_color` and `text_color` are `null` for now. Colours resolve through
the theme after the tree is built, and a partial answer here would misattribute
divergence between "a theme resolved a token to this" and "this was the raw
prop". Honest nulls beat a plausible wrong number, especially when the whole
point of MOB-157 is the framework reporting its own defects.

## Consequences

- Android `Mob.Test.view_tree/1` now returns a normalised map rather than
  `{:error, :not_loaded}`. MOB-157's differential detector can start
  comparing trees.
- The comparison is **semantic tree × id'd geometry**, not "everything about
  the rendered pixels". Fixtures that need geometry-per-node put ids on the
  nodes they want to compare — a deliberate cost that keeps coverage visible.
- The shape matches iOS's `nif_ui_view_tree` at the level MOB-157 needs. What
  iOS returns *more* of — actual painted colours, class names — is
  intentionally not asserted equal until an Android side of that lands.
- A first-round add: only iOS wraps its per-window `UIView` tree in a synthetic
  `root` node whose `frame` is the screen. Android mirrors that here, using the
  activity window's decor view size, so a comparator does not need a platform
  branch for the root.
- Device-verified on an emulator: fresh app, real Mob app produces 4886 bytes
  of JSON — root `[0, 0, 411.4, 914.3]`, structurally `root → scroll → column`
  with every visible button label carried through (17 labels across 40 nodes).

## What this does NOT do

- **No Compose semantics.** Adding a real `SemanticsOwner` walk is a separate
  investment: it gives on-screen text extracted from Compose's accessibility
  layer, plus rendered bounds for nodes without ids. Worth doing when MOB-157
  needs it; the framework tree is enough to compare fixtures against
  fixtures.
- **No paint state.** Colours, borders and typography are absent. If the
  differential detector needs them, a follow-up NIF that samples pixels at
  known points is a smaller commitment than plumbing paint state through the
  bridge.
- **iOS files are app-owned.** Existing apps do not pick this up automatically;
  regenerating or hand-porting `MobBridge.kt` is the same story as every other
  template change (MOB-97, MOB-166).
