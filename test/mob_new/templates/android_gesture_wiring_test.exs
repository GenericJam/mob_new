# Template-assertion test: guards the generated Android gesture wiring (MOB-138).
# credo:disable-for-this-file Jump.CredoChecks.VacuousTest
defmodule MobNew.Templates.AndroidGestureWiringTest do
  use ExUnit.Case, async: true

  @bridge Path.expand(
            "../../../priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex",
            __DIR__
          )

  @jni Path.expand(
         "../../../priv/templates/mob.new/android/app/src/main/jni/beam_jni.c.eex",
         __DIR__
       )

  setup_all do
    {:ok, bridge: File.read!(@bridge), jni: File.read!(@jni)}
  end

  test "long press and double tap are read from the node props", %{bridge: src} do
    # The whole bug was that these props rode along in the JSON and no Kotlin
    # ever looked at them, so the native sender was never reached.
    assert src =~ ~s|intProp(node.props, "on_long_press")|
    assert src =~ ~s|intProp(node.props, "on_double_tap")|
  end

  test "combinedClickable is opt-in, not the default click path", %{bridge: src} do
    # combinedClickable delays the click to wait for a possible second tap.
    # Making it unconditional would add that latency to every ordinary tap in
    # the app, so the branch must be guarded on a handler actually being present.
    assert src =~ "(longPressHandle != null || doubleTapHandle != null)"
    refute src =~ ~r/val tapModifier = when \{\s*\n\s*modifier\.combinedClickable/
  end

  test "the native senders are @JvmStatic", %{bridge: src} do
    # MobBridge is an `object`. Without @JvmStatic these compile to instance
    # methods, so the JNI stub's second parameter is a jobject while the C
    # signature declares jclass. It happens to link, which is exactly why the
    # mismatch survives review unless something asserts on it.
    for fun <- ["nativeSendLongPress", "nativeSendDoubleTap"] do
      assert src =~ ~r/@JvmStatic\s*\n\s*external fun #{fun}\(handle: Int\)/,
             "#{fun} must be declared @JvmStatic"
    end
  end

  test "each Kotlin sender has a matching JNI stub", %{jni: jni} do
    # An external fun with no stub throws UnsatisfiedLinkError at the first
    # gesture rather than at load, so it survives a smoke test that never
    # long-presses anything.
    assert jni =~ "Java_<%= jni_package %>_MobBridge_nativeSendLongPress"
    assert jni =~ "Java_<%= jni_package %>_MobBridge_nativeSendDoubleTap"
    assert jni =~ "mob_send_long_press((int)handle)"
    assert jni =~ "mob_send_double_tap((int)handle)"
  end

  test "the combined branch still delivers a plain tap", %{bridge: src} do
    # A node with both on_tap and on_long_press takes the combined branch and
    # skips the plain clickable arms entirely, so on_tap has to be carried
    # through here or adding a long press silently kills the node's tap.
    combined =
      src
      |> String.split("modifier.combinedClickable(")
      |> Enum.at(1)
      |> String.split("\n\n")
      |> Enum.at(0)

    assert combined =~ "tapHandle?.let { MobBridge.nativeSendTap(it) }"
    assert combined =~ "enabled = !isDisabled"
    assert combined =~ "role = if (isButton) Role.Button else null"
  end

  test "buttons are excluded, matching iOS", %{bridge: src} do
    # Not an oversight and not an Android gap: iOS's `case .button` is the one
    # branch of MobRootView that never applies .mobGestures(node), so a Button
    # with on_long_press drops it on both platforms. Wiring it here alone would
    # make the platforms disagree in the opposite direction.
    assert src =~ ~s|node.type != "button" ->|
  end

  test "swipe is attached only when a swipe handler is declared", %{bridge: src} do
    # detectDragGestures consumes the drag. An unconditional pointerInput would
    # swallow scrolling on every node in the app. iOS gates its DragGesture on
    # exactly this condition for the same reason.
    assert src =~ "val hasSwipe = swipeAny != null || swipeLeft != null"
    assert src =~ "if (!hasSwipe) tapModifier else"
  end

  test "swipe fires the generic handler and the direction-specific one", %{bridge: src} do
    # iOS calls n.onSwipe?(direction) and THEN the matching n.onSwipeLeft?() —
    # a node may declare both and expects both for one gesture. Dropping either
    # would be a silent half-delivery.
    combined =
      src |> String.split("if (direction != null) {") |> Enum.at(1)
          |> String.split("            }\n        }") |> Enum.at(0)

    assert combined =~ "sw.any?.let { MobBridge.nativeSendSwipe(it, direction) }"
    assert combined =~ "sw.left?.let  { MobBridge.nativeSendSwipeLeft(it) }"
    assert combined =~ "sw.down?.let  { MobBridge.nativeSendSwipeDown(it) }"
  end

  test "swipe direction resolves on the dominant axis with a distance floor", %{bridge: src} do
    # Mirrors iOS: abs(dx) > abs(dy) picks horizontal, everything else falls to
    # vertical, and 30dp matches DragGesture(minimumDistance: 30). Without the
    # floor, touch slop alone would emit a swipe for an almost stationary press.
    assert src =~ "val minDistance = 30.dp.toPx()"
    assert src =~ "abs(dx) > abs(dy) && abs(dx) >= minDistance"
    assert src =~ "abs(dy) >= abs(dx) && abs(dy) >= minDistance"
  end

  test "every swipe sender has a JNI stub and reaches the right native fn", %{jni: jni} do
    assert jni =~ "mob_send_swipe_with_direction((int)handle, dir)"
    for d <- ~w(Left Right Up Down) do
      assert jni =~ "Java_<%= jni_package %>_MobBridge_nativeSendSwipe#{d}"
    end
    for d <- ~w(left right up down) do
      assert jni =~ "mob_send_swipe_#{d}((int)handle)"
    end
  end

  test "the swipe direction string is released back to the JVM", %{jni: jni} do
    # GetStringUTFChars without a matching Release leaks a local ref per swipe.
    # A drag-heavy screen would leak steadily and only show up as pressure much
    # later, far from the cause.
    assert jni =~ "ReleaseStringUTFChars(env, direction, dir)"
    assert jni =~ "if (dir == NULL) return;"
  end

  test "the scroll effect is NOT keyed on the tap handles", %{bridge: src} do
    # This is the whole bug that made the first scroll implementation wrong.
    # Every render clears and re-registers the tap table, so each handle int
    # differs frame to frame — and a scroll handler re-renders the screen, which
    # re-registers, which changes the keys. Keying the effect on them restarts
    # it mid-scroll and wipes hasBegun/last/wasPast, so `began` fires on every
    # sample, scrolled_past stops latching, and every delta is measured against
    # a just-reset baseline and comes out 0. Observed: 108 `began` for one swipe.
    assert src =~ "LaunchedEffect(scrollState, horizontal) {"
    refute src =~ "LaunchedEffect(scrollState, scrollH, beganH"
    assert src =~ "rememberUpdatedState(\n        MobScrollHandlers("
  end

  test "scroll reports into the axis the node actually scrolls", %{bridge: src} do
    # A ScrollState is one-dimensional. Reporting a horizontal scroll into y
    # would leave x permanently 0 and vice versa.
    assert src =~ "val x  = if (horizontal) pos.toDouble() else 0.0"
    assert src =~ "val dy = if (horizontal) 0.0 else delta.toDouble()"
  end

  test "top_reached fires on entering the top, not while resting there", %{bridge: src} do
    # Without the `last > 0` half, a screen sitting at offset 0 re-emits on
    # every unrelated recomposition.
    assert src =~ "if (pos <= 0.001f && last > 0.001f)"
  end

  test "scrolled_past is latched to the crossing", %{bridge: src} do
    assert src =~ "if (nowPast && !wasPast)"
    assert src =~ "wasPast = nowPast"
  end

  test "scroll close is debounced and cancels the pending timer", %{bridge: src} do
    # Without the cancel, every sample would schedule its own `ended`.
    assert src =~ "endJob?.cancel()"
    assert src =~ "delay(150)"
  end

  test "the lazy scroll path says so instead of going quiet", %{bridge: src} do
    # The lazy path drives a LazyListState and detaches the pixel ScrollState the
    # observer reads, so the scroll family cannot fire there. Silence is exactly
    # the failure mode this issue exists to remove, so it logs.
    assert src =~ ~s|lazy: true; the scroll event family is pixel-based|
  end

  test "every scroll sender has a JNI stub and releases its phase string", %{jni: jni} do
    for f <- ~w(nativeSendScroll nativeSendScrollBegan nativeSendScrollEnded
                nativeSendScrollSettled nativeSendTopReached nativeSendScrolledPast) do
      assert jni =~ "Java_<%= jni_package %>_MobBridge_#{f}"
    end

    assert jni =~ "ReleaseStringUTFChars(env, phase, ph)"
  end

  test "canvas drag reports dp, not raw pixels", %{bridge: src} do
    # The canvas draws in dp and iOS reports points. Emitting Compose's raw
    # pixels would scale every coordinate by device density, putting the drag in
    # a different space than the drawing it steers.
    assert src =~ "px.toDp().value.toDouble()"
    assert src =~ ~s|val dragged = if (dragHandle == null) sized else|
  end

  test "a cancelled drag still closes", %{bridge: src} do
    # A listener that opened state on "began" is never told to release it
    # otherwise.
    assert src =~ ~s|onDragCancel = { emit(curX, curY, "ended") }|
    assert src =~ ~s|onDragEnd = { emit(curX, curY, "ended") }|
  end

  test "EVERY external sender declared in Kotlin has a JNI stub", %{bridge: src, jni: jni} do
    # Generic, not a list to keep in sync. `nativeSendDrag` shipped without its
    # stub precisely because the per-handler tests each checked only their own
    # senders: Kotlin compiles fine, the app loads fine, and the first drag dies
    # with UnsatisfiedLinkError — a FATAL EXCEPTION on the UI thread, at runtime,
    # only on the one screen that uses it.
    declared =
      Regex.scan(~r/external fun (nativeSend\w+)\(/, src)
      |> Enum.map(fn [_, name] -> name end)
      |> Enum.uniq()

    assert length(declared) > 10, "expected the sender list to be found"

    missing = Enum.reject(declared, &String.contains?(jni, "MobBridge_#{&1}("))

    assert missing == [],
           "Kotlin declares these senders with no JNI stub: #{inspect(missing)}"
  end

  test "no gesture detector is keyed on a tap handle", %{bridge: src} do
    # Handles are re-registered every render. A detector keyed on one is
    # cancelled by any re-render that happens mid-gesture — and on_drag emits
    # continuously, so its own messages cause the re-render that kills it.
    # Observed before the fix: `began` + exactly one `dragging`, then silence,
    # with onDragEnd never running so the drag never closed.
    #
    # Swipe survived this only by accident: it emits nothing until onDragEnd,
    # so nothing re-renders during it. That stops being true the moment the
    # screen updates for any other reason mid-swipe.
    refute src =~ "pointerInput(swipeAny, swipeLeft"
    refute src =~ "pointerInput(dragHandle)"
    assert src =~ "tapModifier.pointerInput(Unit) {"
    assert src =~ "sized.pointerInput(Unit) {"
    assert src =~ "rememberUpdatedState(dragHandle)"
    assert src =~ "MobSwipeHandlers(swipeAny, swipeLeft"
  end

  test "the drag emitter re-reads the live handle each event", %{bridge: src} do
    # Reading the captured `dragHandle` would send to a handle the tap table has
    # already recycled — the message goes nowhere, silently.
    assert src =~ "val h = liveDragHandle ?: return"
  end
end
