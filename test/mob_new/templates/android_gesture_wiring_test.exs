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

  # Whitespace-insensitive containment. String assertions that pin indentation
  # break on a harmless reformat while catching no real regression.
  defp squish(s), do: s |> String.replace(~r/\s+/, " ") |> String.trim()
  defp has?(haystack, needle), do: String.contains?(squish(haystack), squish(needle))

  # ── Wiring exists at all ──────────────────────────────────────────────────

  test "every handler this issue wired is read from the node props", %{bridge: src} do
    for prop <- ~w(on_long_press on_double_tap on_swipe on_swipe_left on_swipe_right
                   on_swipe_up on_swipe_down on_scroll on_scroll_began on_scroll_ended
                   on_scroll_settled on_top_reached on_scrolled_past on_drag) do
      assert has?(src, ~s|intProp(node.props, "#{prop}")|),
             "#{prop} is never read — the native sender stays unreachable"
    end
  end

  test "EVERY external sender declared in Kotlin has a JNI stub", %{bridge: src, jni: jni} do
    # Generic, not a hand-maintained list. `nativeSendDrag` shipped without its
    # stub precisely because the per-handler tests each checked only their own
    # senders: Kotlin compiles, the app loads, and the first drag dies with
    # UnsatisfiedLinkError as a FATAL EXCEPTION on the UI thread.
    declared = declared_senders(src)
    assert length(declared) > 10, "expected to find the sender list"

    missing = Enum.reject(declared, &String.contains?(jni, "MobBridge_#{&1}("))
    assert missing == [], "Kotlin declares these senders with no JNI stub: #{inspect(missing)}"
  end

  test "EVERY external sender is @JvmStatic", %{bridge: src} do
    # MobBridge is an `object`. Without @JvmStatic these compile to instance
    # methods, so the JNI stub's second parameter is really a jobject while the
    # C signature declares jclass. It links by luck.
    not_static =
      Enum.reject(declared_senders(src), fn name ->
        Regex.match?(~r/@JvmStatic\s+external fun #{name}\(/, src)
      end)

    assert not_static == [], "senders missing @JvmStatic: #{inspect(not_static)}"
  end

  # ── The argument order that iOS deliberately reorders ─────────────────────

  test "scroll and drag reach native in (x, y, dx, dy, ...) order", %{jni: jni} do
    # The highest-risk line in the change. iOS's ObjC block is (dx, dy, x, y, …)
    # but mob_send_scroll/mob_send_drag take position first — see mob_beam.h.
    # Swap the pairs in the C stub and every behavioural symptom is subtle:
    # deltas that look like positions, a parallax that drifts.
    assert has?(jni, """
           mob_send_scroll((int)handle, (double)x, (double)y, (double)dx, (double)dy,
                           (double)vx, (double)vy, ph);
           """)

    assert has?(
             jni,
             "mob_send_drag((int)handle, (double)x, (double)y, (double)dx, (double)dy, ph);"
           )
  end

  test "each JNI stub that takes a string releases that string", %{jni: jni} do
    # Counting a single occurrence would let one of the two leak. Pair them per
    # function: a GetStringUTFChars with no matching Release leaks a local ref
    # on every event, which on a drag-heavy screen is continuous.
    for {fun, param} <- [
          {"nativeSendSwipe", "direction"},
          {"nativeSendScroll", "phase"},
          {"nativeSendDrag", "phase"}
        ] do
      body = jni_body(jni, fun)
      assert body =~ "GetStringUTFChars(env, #{param}, NULL)", "#{fun} should read #{param}"
      assert body =~ "ReleaseStringUTFChars(env, #{param}, ", "#{fun} leaks #{param}"
      assert body =~ "== NULL) return;", "#{fun} must bail on a NULL string"
    end
  end

  # ── Gesture attachment: scope and semantics ───────────────────────────────

  test "gestures attach only to the node types iOS gestures", %{bridge: src} do
    # MobRootView applies .mobGestures(node) at exactly five sites — column,
    # row, label, icon, box — out of 25 case branches. Gating on `!= "button"`
    # instead would hand combinedClickable to text_field, toggle, slider and
    # image, which iOS never does; on a text_field that competes with the
    # platform's own long-press text selection.
    assert has?(src, ~s|node.type in setOf("column", "row", "text", "icon", "box")|)
    assert has?(src, "val hasSwipe = gesturableType &&")

    # BOTH press arms must be gated, asserted ARM BY ARM. A whitespace-squished
    # "appears somewhere" check does not work here: the loose needle for arm 2
    # is a literal substring of arm 1's condition, so both assertions are
    # satisfied by arm 1 alone and dropping the gate from arm 2 passes. That
    # exact mutation was demonstrated against the previous version of this test.
    for {label, arm} <- press_arms(src) do
      assert has?(arm, "gesturableType"),
             "the #{label} press arm is not gated on gesturableType"
    end
  end

  test "combinedClickable is used only when the node has a real on_tap", %{bridge: src} do
    # combinedClickable requires an onClick. Passing an empty one publishes a
    # clickable, focusable node with an "activate" action that does nothing —
    # the same misreporting the plain clickable arms were written to avoid.
    assert has?(src, """
           tapHandle != null && (longPressHandle != null || doubleTapHandle != null) &&
             gesturableType ->
           """)

    assert has?(src, "-> { MobBridge.nativeSendTap(tapHandle) }") or
             has?(src, ") { MobBridge.nativeSendTap(tapHandle) }")

    # …and the no-on_tap case uses a raw detector instead.
    assert has?(src, "detectTapGestures(")
    assert has?(src, "onLongPress =")
    assert has?(src, "onDoubleTap =")
  end

  test "combinedClickable is not the default click path", %{bridge: src} do
    # It delays the click while waiting for a second tap, so making it
    # unconditional adds that latency to every tap in the app. Assert the guard
    # is on the arm itself, not merely present somewhere in the file.
    arm =
      src
      |> String.split("modifier.combinedClickable(")
      |> Enum.at(0)
      |> String.split("val tapModifier = when {")
      |> List.last()

    assert has?(arm, "tapHandle != null &&"), "the combinedClickable arm must be guarded"
    assert has?(arm, "gesturableType")
  end

  # ── Swipe ─────────────────────────────────────────────────────────────────

  test "swipe fires the generic handler and the direction-specific one", %{bridge: src} do
    # iOS calls onSwipe(direction) and THEN the matching onSwipeLeft() — a node
    # may declare both and expects both from one gesture.
    assert has?(src, "sw.any?.let { MobBridge.nativeSendSwipe(it, direction) }")

    for {dir, fun} <- [{"left", "Left"}, {"right", "Right"}, {"up", "Up"}, {"down", "Down"}] do
      assert has?(src, ~s|"#{dir}" -> sw.#{dir}?.let { MobBridge.nativeSendSwipe#{fun}(it) }|)
    end
  end

  test "an axis-pure swipe set uses the axis detector so parent scrolling survives",
       %{bridge: src} do
    # detectDragGestures consumes both axes and wins arbitration against an
    # ancestor verticalScroll, so a swipe-to-delete row inside a list would
    # freeze the list — every drag starting on a row swallowed. The axis
    # detectors consume only their own axis.
    # Pin the predicate BODIES, not just the names. Defining swipeHorizontalOnly
    # as `swipeLeft != null || swipeRight != null` — forgetting to exclude the
    # generic handler and the vertical ones — silently kills on_swipe and every
    # vertical swipe on such a node, and a name-only assertion sails past it.
    assert has?(src, """
           val swipeHorizontalOnly =
               swipeAny == null && swipeUp == null && swipeDown == null &&
                   (swipeLeft != null || swipeRight != null)
           """)

    assert has?(src, """
           val swipeVerticalOnly =
               swipeAny == null && swipeLeft == null && swipeRight == null &&
                   (swipeUp != null || swipeDown != null)
           """)

    assert has?(src, "swipeHorizontalOnly -> detectHorizontalDragGestures(")
    assert has?(src, "swipeVerticalOnly -> detectVerticalDragGestures(")
  end

  test "gesture detectors are keyed on the declared structure, not a constant",
       %{bridge: src} do
    # SuspendPointerInputElement compares keys only, so pointerInput(Unit) never
    # restarts: the detector picked at first composition runs forever. A row that
    # starts with on_swipe_left and later gains on_swipe_up would keep the
    # horizontal-only detector; a node narrowing from generic on_swipe to
    # on_swipe_left would keep detectDragGestures and keep freezing its parent
    # list — the exact bug the axis split exists to fix. Keying on the booleans
    # restarts only when the declared set changes, which is never per-render.
    assert has?(src, "tapModifier.pointerInput(swipeHorizontalOnly, swipeVerticalOnly) {")
    assert has?(src, "modifier.pointerInput(longPressHandle != null, doubleTapHandle != null) {")
    refute has?(src, "tapModifier.pointerInput(Unit) {")
  end

  test "text and icon install no clickable of their own", %{bridge: src} do
    # Checked per function, not as one "appears somewhere" assertion: a single
    # shared needle is satisfied by either composable, so weakening only MobIcon
    # would pass. That mutation was demonstrated against the previous version of
    # this test.
    #
    # RenderNodeInner already installs the on_tap clickable and `modifier`
    # carries it in. A second one appended in these functions is innermost, so it
    # won the Main pass, consumed the down, and shadowed the outer one — costing
    # text and icon `enabled = !isDisabled` and the padded hit area, and
    # swallowing the down that on_long_press needs.
    for fun <- ["MobText", "MobIcon"] do
      body = kotlin_fun(src, fun)
      refute body =~ ".clickable", "#{fun} must not install its own clickable"
      refute body =~ "hasPressGestures", "#{fun} should no longer need the press-gesture guard"
    end

    # …and the only clickables left are the two outer arms.
    assert length(String.split(src, "modifier.clickable(")) - 1 == 2
  end

  test "swipe direction resolves on the dominant axis with a distance floor", %{bridge: src} do
    assert has?(src, "val minDistance = 30.dp.toPx()")
    assert has?(src, "abs(dx) > abs(dy) && abs(dx) >= minDistance")
    assert has?(src, "abs(dy) >= abs(dx) && abs(dy) >= minDistance")
  end

  # ── Scroll ────────────────────────────────────────────────────────────────

  test "the scroll observer drops snapshotFlow's initial emission", %{bridge: src} do
    # snapshotFlow emits its current value the moment it is collected. Without
    # the drop, mounting any screen with a scroll handler fires began plus a
    # 150ms-later ended/settled for a scroll that never happened — chrome that
    # hides itself on arrival, analytics for phantom scrolls.
    assert has?(src, "snapshotFlow { scrollState.value }.drop(1).collect")
  end

  test "scroll reports dp, matching iOS points", %{bridge: src} do
    # ScrollState.value is physical pixels; iOS's contentOffset is points, and
    # every threshold an app writes is authored against that. Forwarding pixels
    # makes scrolled_past_threshold: 600 fire after 200dp on a 3x device.
    assert has?(src, "val density = LocalDensity.current")
    assert has?(src, "val pos = with(density) { raw.toDp().value }")
    assert has?(src, "var last = with(density) { scrollState.value.toDp().value }")
  end

  test "scroll reports into the axis the node actually scrolls", %{bridge: src} do
    assert has?(src, "val x = if (horizontal) pos.toDouble() else 0.0")
    assert has?(src, "val dy = if (horizontal) 0.0 else delta.toDouble()")
  end

  test "top_reached fires on entering the top, not while resting there", %{bridge: src} do
    assert has?(src, "if (pos <= 0.001f && last > 0.001f)")
  end

  test "scrolled_past is latched to the crossing", %{bridge: src} do
    assert has?(src, "if (nowPast && !wasPast)")
    assert has?(src, "wasPast = nowPast")
  end

  test "scroll close is debounced and cancels the pending timer", %{bridge: src} do
    assert has?(src, "endJob?.cancel()")
    assert has?(src, "delay(150)")
  end

  test "no scroll observer is installed on the lazy path", %{bridge: src} do
    # The lazy path drives a LazyListState and detaches the pixel ScrollState.
    # Installing the observer anyway would emit nothing useful but would still
    # fire the mount-time began/ended pair, contradicting the warning below it.
    assert has?(src, "if (!isLazyPath) MobScrollEvents(node, scrollState, horizontal)")
  end

  test "the lazy path warns once, not every recomposition", %{bridge: src} do
    # A bare Log.w in the composable body re-fires on every recomposition,
    # which for a scrolling list is every frame.
    assert has?(src, "if (declaresScrollHandlers) { LaunchedEffect(id) {")
    assert has?(src, "is not emitted on the lazy path")
  end

  # ── Handle churn ──────────────────────────────────────────────────────────

  test "no effect or detector is keyed on a tap handle", %{bridge: src} do
    # Handles are re-registered every render, so a detector keyed on one is
    # cancelled by any mid-gesture re-render — and on_drag's own messages cause
    # that re-render. Observed: began + exactly one dragging, then silence.
    refute has?(src, "pointerInput(swipeAny, swipeLeft")
    refute has?(src, "pointerInput(dragHandle)")
    refute has?(src, "LaunchedEffect(scrollState, scrollH, beganH")
    assert has?(src, "tapModifier.pointerInput(swipeHorizontalOnly, swipeVerticalOnly) {")

    # The canvas drag legitimately keys on Unit: whether the block exists at all
    # is decided outside it (`if (dragHandle == null) sized else`), which IS
    # re-evaluated every composition, and the handle itself is read live. There
    # is no structural choice inside the block to go stale.
    assert has?(src, "sized.pointerInput(Unit) {")
    assert has?(src, "rememberUpdatedState(dragHandle)")
  end

  test "emitters re-read the live handle rather than the captured one", %{bridge: src} do
    # A captured handle names a slot the tap table may already have recycled;
    # the message then goes nowhere, silently.
    assert has?(src, "val h = liveDragHandle ?: return")
    assert has?(src, "val sw = liveSwipe")
  end

  # ── Canvas drag ───────────────────────────────────────────────────────────

  test "canvas drag reports dp, not raw pixels", %{bridge: src} do
    assert has?(src, "px.toDp().value.toDouble()")
    assert has?(src, "val dragged = if (dragHandle == null) sized else")
  end

  test "a cancelled drag still closes at the final position", %{bridge: src} do
    # Reporting the drag origin would tell a listener the finger ended where it
    # started; not closing at all leaves state opened on "began" never released.
    assert has?(src, ~s|onDragEnd = { emit(curX, curY, "ended") }|)
    assert has?(src, ~s|onDragCancel = { emit(curX, curY, "ended") }|)
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  # The two press arms of the tapModifier `when`, split on their leading
  # comments so each is checked in isolation.
  defp press_arms(src) do
    body =
      src
      |> String.split("val tapModifier = when {")
      |> Enum.at(1)
      |> String.split("else -> modifier")
      |> Enum.at(0)

    [with_tap, rest] = String.split(body, "// Long press or double tap with NO on_tap", parts: 2)
    no_tap = rest |> String.split("// Require a handler here") |> Enum.at(0)
    [{"with-on_tap", with_tap}, {"no-on_tap", no_tap}]
  end

  # Body of a private Kotlin fun, up to the next top-level declaration.
  defp kotlin_fun(src, name) do
    src
    |> String.split("private fun #{name}(")
    |> Enum.at(1)
    |> String.split(~r/\n(@Composable\n)?private fun /, parts: 2)
    |> Enum.at(0)
  end

  defp declared_senders(src) do
    ~r/external fun (nativeSend\w+)\(/
    |> Regex.scan(src)
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.uniq()
  end

  defp jni_body(jni, fun) do
    case String.split(jni, "MobBridge_#{fun}(") do
      [_, rest | _] -> rest |> String.split("\n}\n") |> List.first()
      _ -> flunk("no JNI stub for #{fun}")
    end
  end
end
