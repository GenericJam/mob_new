defmodule MobNew.Templates.AndroidActivityRelaunchTest do
  use ExUnit.Case, async: true

  @dir Path.expand("../../../priv/templates/mob.new/android/app/src/main/java", __DIR__)

  defp code_only(source) do
    source
    |> String.replace(~r|/\*.*?\*/|s, "")
    |> String.split("\n")
    |> Enum.map_join("\n", &Regex.replace(~r|^\s*//.*$|, &1, ""))
  end

  defp region(source, from, to) do
    [_, rest] = String.split(source, from, parts: 2)
    [body | _] = String.split(rest, to, parts: 2)
    body
  end

  defp squish(source), do: String.replace(source, ~r/\s+/, " ")

  setup_all do
    bridge = File.read!(Path.join(@dir, "MobBridge.kt.eex"))
    main = File.read!(Path.join(@dir, "MainActivity.kt.eex"))
    %{bridge: bridge |> code_only() |> squish(), main: main |> code_only() |> squish()}
  end

  test "the bridge can drop every composition-bound holder", %{bridge: bridge} do
    body = region(bridge, "fun releaseCompositionState() {", "fun frameTrackingModifier")
    # Under the same lock setRootJson takes, with the generation bumped first,
    # so a late frame write from the disposed composition is refused.
    assert body =~ "synchronized(frameLock) { frameGeneration++ elementFramesById.clear() }"
    assert body =~ "lazyListStates.clear()"
    assert body =~ "scrollHandlesById.clear()"
  end

  test "onCreate releases composition state before setContent", %{main: main} do
    on_create = region(main, "override fun onCreate(", "private fun extractPythonAssetsIfNeeded")
    [before_content | _] = String.split(on_create, "setContent {", parts: 2)
    assert before_content =~ "MobBridge.releaseCompositionState()"
  end

  test "the BEAM is started once per process and re-attached afterwards", %{main: main} do
    assert main =~ "private val beamStarted = AtomicBoolean(false)"
    on_create = region(main, "override fun onCreate(", "private fun extractPythonAssetsIfNeeded")
    # nativeSetActivity runs on EVERY create — that is the re-attach.
    assert on_create =~
             "nativeSetActivity(this) if (beamStarted.compareAndSet(false, true)) {"

    assert on_create =~ ~s|Thread({ nativeStartBeam() }, "beam-main").start()|
  end
end
