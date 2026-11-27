# Template-assertion test: guards the identity-preserving screen presentation
# (MOB-146). Everything here is a property of the generated Compose code that
# no Elixir test can execute, and whose regression is a silent slowdown rather
# than a failure.
# credo:disable-for-this-file Jump.CredoChecks.VacuousTest
defmodule MobNew.Templates.AndroidNavIdentityTest do
  use ExUnit.Case, async: true

  @main Application.app_dir(
          :mob_new,
          "priv/templates/mob.new/android/app/src/main/java/MainActivity.kt.eex"
        )

  @bridge Application.app_dir(
            :mob_new,
            "priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex"
          )

  setup_all do
    {:ok, main: File.read!(@main), bridge: File.read!(@bridge)}
  end

  defp squish(s), do: s |> String.replace(~r/\s+/, " ") |> String.trim()
  defp has?(haystack, needle), do: String.contains?(squish(code_only(haystack)), squish(needle))

  # Strip comments before matching. This file explains at length what it does
  # NOT do any more, so a plain substring search would find `AnimatedContent`
  # in the prose describing why it was removed.
  defp code_only(src) do
    src
    |> String.replace(~r|/\*.*?\*/|s, "")
    |> String.split("\n")
    |> Enum.map_join("\n", &Regex.replace(~r|^\s*//.*$|, &1, ""))
  end

  test "navigation does not change composition identity", %{main: src} do
    # The regression this guards cost 420ms per push on a 1600-node screen and
    # raises no error: AnimatedContent wraps its content in key(contentKey), so
    # a changing key disposes the outgoing composition and rebuilds the
    # incoming one from nothing.
    refute has?(src, "AnimatedContent("),
           "AnimatedContent is back — navigation is destroying and rebuilding the tree"

    refute has?(src, "contentKey"),
           "a contentKey on the screen host reintroduces the identity change"

    # AnimatedContent is not the only way back to the bug. A bare `key()` on
    # navKey around the content does exactly the same thing — disposes and
    # rebuilds — and would pass both refutes above.
    refute has?(src, "key(state.navKey)"),
           "keying the content on navKey reintroduces the same 818ms rebuild " <>
             "by a different route"
  end

  test "the outgoing screen is a window copy, never a second mounted tree", %{main: src} do
    # Every navigation convention keeps the outgoing screen visible for the
    # whole transition. A second mounted tree is how AnimatedContent and iOS
    # do it, and here it cost 122ms on every re-render (a parked Compose
    # subtree recomposes with the active one). A copy of the window is pixels:
    # nothing to compose.
    assert has?(src, "PixelCopy.request(window, src, bitmap")

    assert has?(src, "Image( bitmap = out.picture"),
           "the outgoing screen must be drawn from the copy"

    # A layer moves pixels in the draw phase. Modifier.offset is a layout
    # modifier, so it re-runs placement through every mounted node on each of
    # the ~24 frames of the transition.
    assert has?(
             src,
             "graphicsLayer { if (out != null) NavMotion.enter(this, out.transition, progress, widthPx) }"
           ),
           "the incoming screen must animate in the draw phase, not re-place the tree"
  end

  test "the outgoing tree stays on screen, unrecomposed, until it has been copied", %{main: src} do
    # set_root composes and draws the incoming tree before any LaunchedEffect
    # runs. Letting that frame through showed the incoming screen in place for
    # one frame (recorded on a moto g power 2021 and 2024), and would now also
    # put the INCOMING screen into the copy. The last applied ShownScreen is
    # held instead, as the same instance, so NavScreen skips it entirely.
    assert has?(
             src,
             "val shown = if (copying) held!! else remember(state) { ShownScreen(state.node, state.navKey, state.epoch) }"
           ),
           "the held screen must be the same ShownScreen instance, or the copy " <>
             "frame rebuilds the outgoing tree"

    assert has?(src, "SideEffect { committed.value = shown }"),
           "only an applied composition may decide what is held"

    # Equality is identity only for a plain class. A data class compares
    # MobNode trees structurally, on every recomposition.
    assert has?(
             src,
             "@Immutable private class ShownScreen(val node: MobNode?, val navKey: Int, val epoch: Int)"
           )

    # The three writes land in one frame, with nothing that can suspend between
    # them (Animatable.snapTo can): the incoming tree is composed under a copy
    # that still covers it completely, even when it interrupts a transition.
    assert has?(
             src,
             "progress = 0f outgoing = picture?.let { OutgoingScreen(it, transition) } shownNavKey = state.navKey"
           )
  end

  test "the transition clock starts after the incoming tree is drawn", %{main: src} do
    # The frame that builds the incoming tree is the expensive one. Started
    # before it, the animation spent its first ~150ms inside that frame and
    # the outgoing screen vanished in one jump on a moto g power 2021.
    assert has?(
             src,
             "withFrameNanos { } withFrameNanos { } animate(0f, 1f, animationSpec = tween(NavMotion.DURATION_MS, easing = NavMotion.emphasized))"
           )
  end

  test "the motion is a slide over, with no opacity in a push or a pop", %{main: src} do
    # Material's shared axis fades the outgoing screen out before the incoming
    # one fades in; for a few frames both were nearly transparent and a dark
    # header flashed to the background colour and back (moto e, moto g power
    # 2021). A slide over moves opaque screens only.
    assert has?(src, "\"push\" -> layer.translationX = width * (1f - p)")
    assert has?(src, "\"push\" -> layer.translationX = -width * PARALLAX * p")
    assert has?(src, "\"pop\" -> layer.translationX = width * p")
    assert has?(src, "\"pop\" -> layer.translationX = -width * PARALLAX * (1f - p)")

    # The incoming screen must be opaque, or the copy below shows through it.
    assert has?(
             src,
             ".graphicsLayer { if (out != null) NavMotion.enter(this, out.transition, progress, widthPx) } .background(MaterialTheme.colorScheme.background)"
           )

    # A push covers the outgoing screen, a pop uncovers the incoming one.
    assert has?(src, ".zIndex(if (out.transition == \"push\") -1f else 1f)")

    assert has?(
             src,
             "cubicTo(0.05f, 0f, 0.133333f, 0.06f, 0.166666f, 0.4f) cubicTo(0.208333f, 0.82f, 0.25f, 1f, 1f, 1f)"
           ),
           "the easing must be md.sys.motion.easing.emphasized"
  end

  test "the transition is keyed on navKey, never on the whole state", %{main: src} do
    # This one rendered a BLANK SCREEN, and silently: LaunchedEffect cancels
    # its coroutine when the key changes, and `state` is a new RootState on
    # every render. Keyed on `state`, any re-render arriving during a
    # transition — a timer, an async mount, a subscription — cancelled the
    # animation and froze it. The BEAM went on reporting the correct screen
    # and assigns, so nothing driving the app over dist could see it.
    # Reproduced on device by sending one re-render 100ms after a navigation.
    assert has?(src, "LaunchedEffect(state.navKey)"),
           "the transition must be keyed on navKey, so an ordinary re-render " <>
             "cannot cancel it"

    refute has?(src, "LaunchedEffect(state) {"),
           "keying the transition on the whole state leaves the screen blank " <>
             "whenever a render lands during a navigation"
  end

  test "a navigation that cannot be copied still shows the incoming screen", %{main: src} do
    # No window, no bounds yet, no tree on screen (first mount), or a copy
    # that fails: the incoming screen is shown at once, with no transition,
    # rather than held until a copy that never comes.
    assert has?(src, "if (src.isEmpty) return null")
    assert has?(src, "if (state.navKey == shownNavKey) return@LaunchedEffect")
    assert has?(src, "if (cont.isActive) cont.resume(null)")
  end

  test "a copy is never drawn at a size other than the one it was taken at", %{main: src} do
    # A rotation mid-transition (seen on a moto g power 2021) changes the
    # host's bounds; FillBounds would stretch the portrait copy across them.
    assert has?(
             src,
             "it.width.roundToInt() == o.picture.width && it.height.roundToInt() == o.picture.height"
           )
  end

  test "nothing under a transition takes input or accessibility focus", %{main: src} do
    # On a pop or a reset the copy is drawn over the live incoming screen, so
    # without a shield every tap during the 400ms reached a control nobody
    # could see.
    assert has?(src, "Modifier.matchParentSize().zIndex(2f).pointerInput(Unit)")
    assert has?(src, ".then(if (out != null) Modifier.clearAndSetSemantics {} else Modifier)")
  end

  test "a SurfaceView is in the copy, not a hole", %{main: src} do
    # A window PixelCopy leaves a transparent hole where a SurfaceView (a
    # gpu_view, a camera preview) composites; the copy would carry it through
    # the transition.
    assert has?(src, "MobBridge.collectSurfaceViews(window.decorView, surfaces)")
    assert has?(src, "PixelCopy.request(view, bitmap, listener, handler)")
  end

  test "navigation re-keys the frame trackers", %{main: main, bridge: bridge} do
    # Without this the failure is silent and delayed. The mount point now
    # persists across navigation, so nodes Compose reuses keep the generation
    # they captured for the PREVIOUS screen — which setRootJson has just
    # superseded. Their frame writes are refused for ever, element_frames
    # quietly loses those ids, and tap_id stops finding them.
    #
    # navKey is the epoch: it moves on every non-"none" transition and nothing
    # else, which is exactly when the trackers must re-capture.
    # Containment, not mere presence. A provider wrapping an empty body, with
    # RenderNode moved outside it, passes a presence check while every tracked
    # node reads the default epoch 0 for ever — so after the first navigation
    # every frame write is refused, element_frames returns nothing and tap_id
    # finds nothing, with no error anywhere.
    assert has?(
             main,
             "CompositionLocalProvider( MobBridge.LocalSlotEpoch provides shown.navKey, LocalRenderEpoch provides shown.epoch, ) { RenderNode(node"
           ),
           "RenderNode must be INSIDE the epoch providers"

    assert has?(bridge, "val epoch = LocalSlotEpoch.current"),
           "frameTrackingModifier must read the epoch"

    assert has?(bridge, "remember(id, epoch) { currentFrameGeneration() }"),
           "the generation capture must be keyed on the epoch, or reused nodes " <>
             "keep a stale generation and their frames are refused"
  end
end
