# Template-assertion test: the Android element-frame registry refuses writes
# from a screen that is animating away (MOB-142). iOS carries the same gate
# after MOB-102 / MOB-103.
# credo:disable-for-this-file Jump.CredoChecks.VacuousTest
defmodule MobNew.Templates.AndroidFrameGenerationTest do
  use ExUnit.Case, async: true

  @bridge Path.expand(
            "../../../priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex",
            __DIR__
          )

  @main_activity Path.expand(
                   "../../../priv/templates/mob.new/android/app/src/main/java/MainActivity.kt.eex",
                   __DIR__
                 )

  setup_all do
    {:ok, src: File.read!(@bridge), main: File.read!(@main_activity)}
  end

  defp squish(s), do: s |> String.replace(~r/\s+/, " ") |> String.trim()
  defp has?(hay, needle), do: String.contains?(squish(hay), squish(needle))

  # Kotlin source with comments removed. Every assertion below runs on the
  # output of this, because the implementation it guards is surrounded by long
  # prose explaining the very mechanism being asserted: an assertion a comment
  # could satisfy would pass against code that does nothing.
  defp code_only(src) do
    src
    |> String.replace(~r{/\*.*?\*/}s, "")
    |> String.replace(~r{//[^\n]*}, "")
  end

  # The registry section: the map, the counter, recordElementFrame and the
  # tracking modifier, stopping before the elementFrames() serialiser.
  defp registry(src) do
    src
    |> String.split("private val elementFramesById")
    |> Enum.at(1)
    |> String.split("/** JSON {id:")
    |> Enum.at(0)
    |> code_only()
  end

  defp set_root(src) do
    src
    |> String.split("fun setRootJson(json: String, transition: String) {")
    |> Enum.at(1)
    |> String.split("\n    }\n")
    |> Enum.at(0)
    |> code_only()
  end

  defp fun_body(section, header) do
    section
    |> String.split(header)
    |> Enum.at(1)
    |> String.split("\n    }")
    |> Enum.at(0)
  end

  # Byte offset of a needle in the squished haystack, so a test can assert that
  # one statement precedes another rather than only that both exist.
  defp at(hay, needle) do
    case :binary.match(squish(hay), squish(needle)) do
      {i, _} -> i
      :nomatch -> flunk("expected to find #{inspect(needle)}")
    end
  end

  test "recordElementFrame gates the write on the caller's generation", %{src: src} do
    body = fun_body(registry(src), "fun recordElementFrame(")

    # The write path used to take no generation at all, which is the bug: the
    # clear in setRootJson had nothing to stop the outgoing screen refilling
    # the map as AnimatedContent slid it off.
    assert has?(body, "id: String, generation: Long, x: Float, y: Float, w: Float, h: Float")

    # The guard is the first statement, so the map write cannot be reached
    # without passing it. Asserting them as one squished run pins the order,
    # not just the presence of both.
    # The check and the write are one critical section, not two statements that
    # happen to be adjacent. An atomic counter beside an unguarded map makes
    # each access safe and still loses the race: a tracker can read a
    # generation that is still current, lose the thread, and have setRootJson
    # bump and clear before its write lands. Asserting them as one squished run
    # inside synchronized pins that, not just their presence and order.
    assert has?(
             body,
             "synchronized(frameLock) { if (generation < frameGeneration) return " <>
               "elementFramesById[id] = floatArrayOf"
           )
  end

  test "the gate refuses stale writes, not fresh ones", %{src: src} do
    body = fun_body(registry(src), "fun recordElementFrame(")

    # Inverting the comparison keeps a gate-shaped line in place while
    # rejecting exactly the writes that should be kept: the incoming screen's.
    # The registry would then hold whatever the outgoing screen last wrote,
    # which is worse than no gate, so each inverted spelling is refuted.
    assert has?(body, "if (generation < frameGeneration) return")
    refute has?(body, "generation > frameGeneration)")
    refute has?(body, "generation != frameGeneration)")
    refute has?(body, "frameGeneration < generation")
    refute has?(body, "frameGeneration > generation")
  end

  test "the tracker captures the generation once, not per recomposition", %{src: src} do
    reg = registry(src)

    # Reading the counter at write time, or under a remember keyed on the
    # counter itself, means a write can never be older than the current
    # generation and the gate can never refuse anything. That mutant reads as
    # a fix and behaves like the bug, so it is refuted explicitly rather than
    # left to the positive assertion alone.
    assert has?(reg, "@Composable fun frameTrackingModifier(id: String): Modifier {")
    assert has?(reg, "val generation = remember(id) { currentFrameGeneration() }")

    refute has?(reg, "remember(currentFrameGeneration())")
    refute has?(reg, "recordElementFrame(id, currentFrameGeneration()")
    refute has?(reg, "recordElementFrame(id, frameGeneration,")

    # A keyless remember would survive a composition slot being handed a
    # different :id, which outside column / row / the lazy list is positional
    # and so genuinely happens.
    refute has?(reg, "remember { currentFrameGeneration() }")

    # And the captured value, not a fresh read, is what every write carries.
    assert has?(reg, "recordElementFrame(id, generation, b.left, b.top, b.width, b.height)")
  end

  test "setRootJson bumps the generation before clearing and before publishing", %{src: src} do
    body = set_root(src)

    bump = at(body, "frameGeneration++")

    # Before the clear: both run on the NIF thread while Compose may be laying
    # out, so a write landing between a clear and a later bump would be
    # accepted and would survive.
    assert bump < at(body, "elementFramesById.clear()")

    # Before the state write: composition of the incoming tree is what that
    # write schedules, so this ordering is what guarantees the incoming
    # trackers capture the new value and the outgoing ones keep the old.
    assert bump < at(body, "_rootState.value = RootState(newKey")

    # And only on a real navigation, in lockstep with the clear it protects.
    assert at(body, ~s|if (transition != "none") {|) < bump
    assert bump < at(body, "} else {")
  end

  test "the generation is its own monotonic counter, not navKey", %{src: src, main: main} do
    # navKey is the AnimatedContent contentKey, so it describes animation
    # identity rather than registry liveness, and it lives in a Compose
    # snapshot state: a tracker reading it would be resubscribed on every root
    # update, and the outgoing tree recomposing during its exit animation would
    # read the INCOMING navKey and restamp itself.
    assert has?(main, "it.navKey")
    assert has?(code_only(src), "private var frameGeneration = 1L")

    refute has?(registry(src), "navKey")
    refute has?(registry(src), "rootState")
  end

  test "one monitor covers the counter and the registry, not just the counter", %{src: src} do
    # An AtomicLong beside an unguarded map is the tempting version and is
    # unsound: each access is atomic, and recordElementFrame is still a
    # check-then-act across two objects. ConcurrentHashMap.clear() is not
    # atomic against a concurrent put either, so ordering the bump before the
    # clear narrows the window without closing it. iOS closes it by putting the
    # check, the write and the bump under one monitor; so does this.
    reg = registry(src)

    assert has?(reg, "private val frameLock = Any()")

    assert has?(
             reg,
             "fun currentFrameGeneration(): Long = synchronized(frameLock) { frameGeneration }"
           )

    # The bump and the clear it protects are the same critical section.
    assert has?(
             set_root(src),
             "synchronized(frameLock) { frameGeneration++ elementFramesById.clear() }"
           )

    refute has?(code_only(src), "AtomicLong"),
           "an atomic counter beside an unguarded map is the unsound version"
  end

  test "the tracking modifier is actually attached to rendered nodes", %{src: src} do
    # Nothing else in this file can see the call site. Deleting it leaves the
    # gate, the counter and every assertion above intact and green while
    # element_frames and tap_id stop working altogether, which is a far worse
    # outcome than the bug this issue fixes.
    code = code_only(src)

    assert has?(code, "val trackId = node.props[\"id\"] as? String")

    assert has?(
             code,
             "val m = if (trackId != null) base.then(MobBridge.frameTrackingModifier(trackId)) else base"
           )
  end
end
