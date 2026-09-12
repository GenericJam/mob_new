defmodule MobNew.Templates.AndroidRangeSliderTest do
  use ExUnit.Case, async: true

  @bridge Path.expand(
            "../../../priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex",
            __DIR__
          )

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
    %{
      code:
        @bridge
        |> File.read!()
        |> region("private fun MobSlider(", "private fun MobDivider")
        |> code_only()
        |> squish()
    }
  end

  test "a `values` pair routes to the two-thumb control, a single value stays on Slider",
       %{code: code} do
    assert code =~ ~s|val range = floatListProp(node.props, "values")|

    assert code =~
             "if (range != null) { MobRangeSlider(node, modifier, range, minVal, maxVal, steps, colors, handle) return }"

    # Only a pair counts; anything shorter is not a range.
    assert code =~ "raw?.takeIf { it.size >= 2 }?.let { listOf(it[0], it[1]) }"
  end

  test "the pair goes back over the string change channel as lo,hi", %{code: code} do
    assert code =~ ~s|MobBridge.nativeSendChangeStr(it, "${local.first},${local.second}")|
    assert code =~ ~s|val stop = (node.props["collision"] as? String) == "stop"|
    assert code =~ ~s|val gap = floatProp(node.props, "min_gap") ?: 0f|
  end

  test "steps snap natively and a vertical slider is a rotated horizontal one", %{code: code} do
    assert code =~ ~s|val steps = intProp(node.props, "steps")?.coerceAtLeast(0) ?: 0|
    assert code =~ "steps = steps,"
    assert code =~ "MobSliderBody(node, Modifier.width(len.dp).rotate(-90f))"
  end
end
