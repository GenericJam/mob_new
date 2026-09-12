defmodule MobNew.Templates.AndroidToggleTrackColorTest do
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

  test "track_color tints the track and only when supplied" do
    code =
      @bridge
      |> File.read!()
      |> region("private fun MobToggle", "private fun MobSlider(")
      |> code_only()
      |> squish()

    assert code =~ ~s|val track = colorProp(node.props, "track_color")|

    assert code =~
             "color != Color.Unspecified && track != Color.Unspecified -> SwitchDefaults.colors(checkedThumbColor = color, checkedTrackColor = track)"

    assert code =~
             "track != Color.Unspecified -> SwitchDefaults.colors(checkedTrackColor = track)"

    # An unset pair keeps Material's defaults rather than Unspecified.
    assert code =~ "else -> SwitchDefaults.colors()"
    assert code =~ "colors = switchColors,"
  end
end
