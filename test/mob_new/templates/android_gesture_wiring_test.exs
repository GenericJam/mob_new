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

    assert combined =~ "swipeAny?.let { MobBridge.nativeSendSwipe(it, direction) }"
    assert combined =~ "swipeLeft?.let  { MobBridge.nativeSendSwipeLeft(it) }"
    assert combined =~ "swipeDown?.let  { MobBridge.nativeSendSwipeDown(it) }"
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
end
