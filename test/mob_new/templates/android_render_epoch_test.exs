defmodule MobNew.Templates.AndroidRenderEpochTest do
  use ExUnit.Case, async: true

  @dir Application.app_dir(:mob_new, "priv/templates/mob.new/android/app/src/main/java")

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

  test "the text field resyncs on a new epoch through MobTextSync, controlled fields only",
       %{bridge: bridge} do
    code =
      bridge
      |> region("private fun MobTextField", "private fun MobToggle")
      |> code_only()
      |> squish()

    # Not re-keyed on the value: an equal value after a rejected keystroke
    # must still be adopted.
    refute code =~ ~s|remember(node.props["value"]|
    assert code =~ "val epoch = LocalRenderEpoch.current"

    # MOB-309: a pushed value is weighed against what this field sent, not
    # adopted whenever it disagrees, and only for a field that has a value.
    refute code =~ "if (incoming != localValue) localValue = incoming"
    assert code =~ ~s|val controlled = node.props.containsKey("value")|

    assert code =~
             "if (epoch != seenEpoch) { seenEpoch = epoch if (controlled) { sync.rendered(incoming, field.text)?.let { adopted ->"

    # Every reported edit is recorded, or its echo would read as a BEAM change.
    assert code =~
             "if (textChanged) { changeHandle?.let { sync.sent(new.text) MobBridge.nativeSendChangeStr(it, new.text) } }"

    # Navigation resets the field's state (MOB-146): the mount point survives it.
    assert code =~ "val sync = remember(slotEpoch) { MobTextSync() }"
    assert code =~ "var field by remember(slotEpoch) {"
    assert code =~ "var seenEpoch by remember(slotEpoch) { mutableStateOf(epoch) }"
  end

  test "the slider follows the finger during a drag and the BEAM otherwise", %{bridge: bridge} do
    code =
      bridge
      |> region("private fun MobSlider", "private fun MobDivider")
      |> code_only()
      |> squish()

    refute code =~ ~s|remember(node.props["value"]|
    # The epoch is stamped only between drags: a render landing mid-drag (the
    # BEAM's clamped final value) must still be adopted on release.
    assert code =~ "if (!dragging && epoch != seenEpoch) { seenEpoch = epoch"
    assert code =~ "if (incomingVal != localVal) localVal = incomingVal"
    # The range slider reads the current handle, not the one captured when the
    # pointerInput lambda was keyed.
    assert code =~ "val liveHandle by rememberUpdatedState(handle)"

    assert code =~
             ~s|liveHandle?.let { MobBridge.nativeSendChangeStr(it, "${local.first},${local.second}") }|

    assert code =~ "onValueChange = { new -> dragging = true localVal = new"
    assert code =~ "onValueChangeFinished = { dragging = false },"
  end
end
