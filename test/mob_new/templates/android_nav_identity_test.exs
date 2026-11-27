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

  test "the slide is driven by an animated offset", %{main: src} do
    # Enter/exit transitions only fire on insert/remove, and insert/remove is
    # exactly what the identity change cost. Driving the offset directly is
    # what decouples the animation from identity.
    assert has?(src, "Animatable(0f)")

    # Both halves. Asserting only animateTo lets the parking snap be deleted,
    # which leaves a push animating 0 -> 0: no error, no slide.
    assert has?(src, "offset.snapTo(from)"),
           "the incoming screen must be parked before it is animated in"

    assert has?(src, "offset.animateTo(0f, tween(durationMillis = 300))")

    # A layer translation moves pixels in the draw phase. Modifier.offset is a
    # layout modifier, so it re-runs placement through every mounted node on
    # each of the ~18 frames of the slide.
    assert has?(src, "graphicsLayer { translationX = pendingFrom ?: offset.value }"),
           "the slide must translate in the draw phase, not re-place the tree"
  end

  test "the incoming screen's first frame is already parked", %{main: src} do
    # set_root composes and draws the incoming tree one frame before any
    # LaunchedEffect runs. With the offset only parked from the effect, that
    # frame showed the incoming screen in place, which then vanished and slid
    # back in: a one-frame flash on every push and pop, recorded on a moto g
    # power 2021 and 2024. The start position has to come from composition.
    assert has?(
             src,
             "if (slidNavKey != state.navKey) slideFrom(state.transition, containerWidth) else null"
           ),
           "the parked position must be applied in the composition that mounts the new tree"

    # Handing back to `offset` before the snap would draw one frame at rest.
    assert has?(src, "offset.snapTo(from) slidNavKey = state.navKey"),
           "the effect must take over only once the offset is parked"
  end

  test "the slide animation is keyed on navKey, never on the whole state", %{main: src} do
    # This one rendered a BLANK SCREEN, and silently: LaunchedEffect cancels
    # its coroutine when the key changes, and `state` is a new RootState on
    # every render. Keyed on `state`, any re-render arriving during the 300ms
    # slide — a timer, an async mount, a subscription — cancelled animateTo and
    # left the offset frozen off-canvas. The BEAM went on reporting the correct
    # screen and assigns, so nothing driving the app over dist could see it.
    # Reproduced on device by sending one re-render 100ms after a navigation.
    assert has?(src, "LaunchedEffect(state.navKey)"),
           "the animation must be keyed on navKey, so an ordinary re-render " <>
             "cannot cancel it mid-slide"

    refute has?(src, "LaunchedEffect(state) {"),
           "keying the animation on the whole state leaves the screen blank " <>
             "whenever a render lands during a navigation"
  end

  test "an interrupted slide still returns the offset to rest", %{main: src} do
    # The snap is unconditional, before any animation: with no slide (reset,
    # first mount, width unknown) `from` is 0, and that snap is what recovers
    # the offset if a previous slide was interrupted before reaching 0.
    assert has?(src, "val from = slideFrom(state.transition, containerWidth) offset.snapTo(from)")
    assert has?(src, "width <= 0 -> 0f")
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
             "CompositionLocalProvider(MobBridge.LocalSlotEpoch provides state.navKey) { RenderNode(node"
           ),
           "RenderNode must be INSIDE the epoch provider"

    assert has?(bridge, "val epoch = LocalSlotEpoch.current"),
           "frameTrackingModifier must read the epoch"

    assert has?(bridge, "remember(id, epoch) { currentFrameGeneration() }"),
           "the generation capture must be keyed on the epoch, or reused nodes " <>
             "keep a stale generation and their frames are refused"
  end
end
