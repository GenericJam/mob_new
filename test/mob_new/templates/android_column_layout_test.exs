# Template-assertion tests for Android container constraint ordering (MOB-233).
# credo:disable-for-this-file Jump.CredoChecks.VacuousTest
defmodule MobNew.Templates.AndroidColumnLayoutTest do
  use ExUnit.Case, async: true

  @bridge Path.expand(
            "../../../priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex",
            __DIR__
          )

  setup_all do
    source = File.read!(@bridge)
    helper = source |> String.split("private fun nodeModifier(") |> Enum.at(1)
    {:ok, helper: helper}
  end

  test "fixed dimensions wrap fill constraints rather than sitting inside them", %{helper: helper} do
    width_at = byte_offset(helper, "fixedWidth?.let  { w -> m = m.width(w.dp) }")
    height_at = byte_offset(helper, "fixedHeight?.let { h -> m = m.height(h.dp) }")
    fill_width_at = byte_offset(helper, "if (fillWidth && fixedWidth == null)")
    fill_height_at = byte_offset(helper, "if (fillHeight && fixedHeight == null)")

    assert width_at < fill_width_at
    assert width_at < fill_height_at
    assert height_at < fill_width_at
    assert height_at < fill_height_at
  end

  test "a fixed dimension suppresses fill only on the same axis", %{helper: helper} do
    assert helper =~ "if (fillWidth && fixedWidth == null) m = m.fillMaxWidth()"
    assert helper =~ "if (fillHeight && fixedHeight == null) m = m.fillMaxHeight()"
  end

  test "only positive dimensions suppress fill, matching iOS", %{helper: helper} do
    assert helper =~ ~s|floatProp(props, "width")?.takeIf { it > 0f }|
    assert helper =~ ~s|floatProp(props, "height")?.takeIf { it > 0f }|
  end

  defp byte_offset(source, needle) do
    {offset, _length} = :binary.match(source, needle)
    offset
  end
end
