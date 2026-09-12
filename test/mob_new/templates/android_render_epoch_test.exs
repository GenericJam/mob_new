defmodule MobNew.Templates.AndroidRenderEpochTest do
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
    %{bridge: bridge, main: main |> code_only() |> squish()}
  end

  test "every set_root bumps the epoch, navigation or not", %{bridge: bridge} do
    code = bridge |> code_only() |> squish()
    assert code =~ "val epoch: Int = 0, )"
    assert code =~ "val LocalRenderEpoch = androidx.compose.runtime.compositionLocalOf { -1 }"

    assert code =~
             "_rootState.value = RootState(newKey, transition, parsed, _rootState.value.epoch + 1)"
  end

  test "MainActivity provides the epoch above the whole tree", %{main: main} do
    assert main =~
             "CompositionLocalProvider(LocalRenderEpoch provides state.epoch) { MaterialTheme(colorScheme = colorScheme) { MobNavHost(state) } }"
  end

  test "the text field resyncs on a new epoch only when the value disagrees", %{bridge: bridge} do
    code =
      bridge
      |> region("private fun MobTextField", "private fun MobToggle")
      |> code_only()
      |> squish()

    # Not re-keyed on the value: an equal value after a rejected keystroke
    # must still be adopted, and the slot epoch is subsumed by the render epoch.
    refute code =~ ~s|remember(node.props["value"]|
    assert code =~ "val epoch = LocalRenderEpoch.current"
    assert code =~ "var seenEpoch by remember { mutableStateOf(-1) }"

    assert code =~
             "if (epoch != seenEpoch) { seenEpoch = epoch if (incoming != localValue) localValue = incoming }"
  end

  test "the slider follows the finger during a drag and the BEAM otherwise", %{bridge: bridge} do
    code =
      bridge
      |> region("private fun MobSlider", "private fun MobDivider")
      |> code_only()
      |> squish()

    refute code =~ ~s|remember(node.props["value"]|
    assert code =~ "if (!dragging && incomingVal != localVal) localVal = incomingVal"
    assert code =~ "onValueChange = { new -> dragging = true localVal = new"
    assert code =~ "onValueChangeFinished = { dragging = false },"
  end
end
