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
    assert has?(
             body,
             "{ if (generation < frameGeneration.get()) return elementFramesById[id] = floatArrayOf"
           )
  end

  test "the gate refuses stale writes, not fresh ones", %{src: src} do
    body = fun_body(registry(src), "fun recordElementFrame(")

    # Inverting the comparison keeps a gate-shaped line in place while
    # rejecting exactly the writes that should be kept: the incoming screen's.
    # The registry would then hold whatever the outgoing screen last wrote,
    # which is worse than no gate, so each inverted spelling is refuted.
    assert has?(body, "if (generation < frameGeneration.get()) return")
    refute has?(body, "generation > frameGeneration.get()")
    refute has?(body, "generation != frameGeneration.get()")
    refute has?(body, "frameGeneration.get() < generation")
    refute has?(body, "frameGeneration.get() > generation")
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
    refute has?(reg, "recordElementFrame(id, frameGeneration.get()")

    # A keyless remember would survive a composition slot being handed a
    # different :id, which outside column / row / the lazy list is positional
    # and so genuinely happens.
    refute has?(reg, "remember { currentFrameGeneration() }")

    # And the captured value, not a fresh read, is what every write carries.
    assert has?(reg, "recordElementFrame(id, generation, b.left, b.top, b.width, b.height)")
  end

  test "setRootJson bumps the generation before clearing and before publishing", %{src: src} do
    body = set_root(src)

    bump = at(body, "frameGeneration.incrementAndGet()")

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
    assert has?(main, "contentKey    = { it.navKey }")
    assert has?(code_only(src), "private val frameGeneration = AtomicLong(1L)")

    refute has?(registry(src), "navKey")
    refute has?(registry(src), "rootState")
  end

  test "the counter is safe to read from the Compose thread", %{src: src} do
    # Bumped on the NIF/binder thread inside setRootJson, read on the Compose
    # main thread by both the capture and the gate. A plain Long would leave
    # that read with no visibility guarantee; AtomicLong makes each access a
    # single atomic one and adds no lock to order against elementFramesById.
    assert has?(code_only(src), "import java.util.concurrent.atomic.AtomicLong")
    refute has?(registry(src), "private var frameGeneration")
    assert has?(registry(src), "fun currentFrameGeneration(): Long = frameGeneration.get()")
  end
end
