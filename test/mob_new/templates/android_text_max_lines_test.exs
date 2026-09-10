defmodule MobNew.Templates.AndroidTextMaxLinesTest do
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

  test "a text node caps its lines and ellipsises only when max_lines is set" do
    source =
      @bridge
      |> File.read!()
      |> region("private fun MobText", "private fun MobButton")
      |> code_only()
      |> squish()

    assert source =~ ~s|val maxLines = intProp(node.props, "max_lines")?.takeIf { it > 0 }|

    # Unset must fall back to Compose's own defaults (Int.MAX_VALUE / Clip),
    # not to some other limit, so an app without the prop renders as before.
    assert source =~ "maxLines = maxLines ?: Int.MAX_VALUE,"

    assert source =~
             "overflow = if (maxLines != null) TextOverflow.Ellipsis else TextOverflow.Clip,"
  end
end
