# Template-assertion test: `clip_width` / `clip_height` on the generated
# Android bridge (the Android half of mob's props). The clip is Compose draw
# code the host suite cannot run, so these pin the lines whose loss would break
# the contract silently: the props are read, the clip is a draw-time clipRect,
# it wraps everything nodeModifier draws, and clip_width keeps the leading side.
defmodule MobNew.Templates.AndroidClipFractionTest do
  use ExUnit.Case, async: true

  @bridge Application.app_dir(
            :mob_new,
            "priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex"
          )

  setup_all do
    source = File.read!(@bridge)

    %{
      clip:
        source
        |> region("private fun mobFractionClip(", "\n}\n")
        |> code_only()
        |> squish(),
      node_modifier:
        source |> region("private fun nodeModifier(", "\n}\n") |> code_only() |> squish()
    }
  end

  defp code_only(source) do
    source
    |> String.replace(~r|/\*.*?\*/|s, "")
    |> String.split("\n")
    |> Enum.map_join("\n", &Regex.replace(~r|//.*$|, &1, ""))
  end

  defp region(source, from, to) do
    [_, rest] = String.split(source, from, parts: 2)
    [body | _] = String.split(rest, to, parts: 2)
    body
  end

  defp squish(source), do: String.replace(source, ~r/\s+/, " ")

  test "both props are read as clamped fractions, defaulting to no clip", %{clip: clip} do
    assert clip =~ ~s|val keepWidth = floatProp(props, "clip_width")?.coerceIn(0f, 1f) ?: 1f|
    assert clip =~ ~s|val keepHeight = floatProp(props, "clip_height")?.coerceIn(0f, 1f) ?: 1f|

    # Absent or >= 1 on both axes: nothing added to the chain.
    assert clip =~ "if (keepWidth >= 1f && keepHeight >= 1f) return Modifier"

    # <= 0 on either axis: nothing drawn at all.
    assert clip =~ "if (keepWidth <= 0f || keepHeight <= 0f) return@drawWithContent"
  end

  test "the clip is draw-time: a clipRect around drawContent, no layout modifier", %{
    clip: clip
  } do
    assert clip =~ "return Modifier.drawWithContent {"

    assert clip =~
             "clipRect(left = left, top = top, right = right, bottom = bottom) " <>
               "{ this@drawWithContent.drawContent() }"

    # A size modifier would change what the parent lays out.
    refute clip =~ ~r/\.(width|height|size|requiredSize|layout|clip)\(/
  end

  test "each prop cuts only its own axis; the other stays open for overflow", %{clip: clip} do
    # Horizontal band is open unless clip_width cuts it.
    assert clip =~
             "var left = -MOB_CLIP_UNBOUNDED var right = MOB_CLIP_UNBOUNDED if (keepWidth < 1f) {"

    assert clip =~ "right = left + visibleWidth"

    # Vertical band is open unless clip_height cuts it; it keeps the top.
    assert clip =~ "val top = if (keepHeight < 1f) 0f else -MOB_CLIP_UNBOUNDED"

    assert clip =~
             "val bottom = if (keepHeight < 1f) size.height * keepHeight else MOB_CLIP_UNBOUNDED"
  end

  test "clip_width keeps the leading side: the left in LTR, the right in RTL", %{clip: clip} do
    assert clip =~ "val visibleWidth = size.width * keepWidth"

    assert clip =~
             "left = if (layoutDirection == LayoutDirection.Rtl) " <>
               "size.width - visibleWidth else 0f"
  end

  test "the clip heads nodeModifier, so it wraps the background, border and children", %{
    node_modifier: node_modifier
  } do
    assert node_modifier =~
             ~r/^\s*props: Map<String, Any\?>\): Modifier \{ var m: Modifier = mobFractionClip\(props\) /

    # Everything nodeModifier draws comes after it in the chain.
    clip = :binary.match(node_modifier, "mobFractionClip(props)") |> elem(0)

    for drawn <- ["m.background(", "m.border(", "m.clip(shape)"] do
      assert clip < :binary.match(node_modifier, drawn) |> elem(0), drawn
    end
  end
end
