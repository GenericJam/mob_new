# Template-assertion tests for the measured Android wrap layout (MOB-175).
# credo:disable-for-this-file Jump.CredoChecks.VacuousTest
defmodule MobNew.Templates.AndroidWrapLayoutTest do
  use ExUnit.Case, async: true

  @bridge Path.expand(
            "../../../priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex",
            __DIR__
          )

  setup_all do
    {:ok, source: File.read!(@bridge)}
  end

  test "wrap renders with native FlowRow and independent axis spacing", %{source: source} do
    assert source =~ "import androidx.compose.foundation.layout.FlowRow"
    assert source =~ "ExperimentalLayoutApi::class"
    assert source =~ ~s|"wrap" -> FlowRow(|
    assert source =~ ~s|floatProp(node.props, "spacing")|
    assert source =~ ~s|floatProp(node.props, "run_spacing")|
  end

  test "wrap children keep authored identity", %{source: source} do
    wrap_branch = source |> String.split(~s|"wrap" -> FlowRow(|) |> Enum.at(1)

    assert wrap_branch =~ "val keys = mobChildKeys(node.children)"
    assert wrap_branch =~ "key(keys[i]) { RenderNode(child) }"
  end

  test "wrap supports the same extended gestures on both platforms", %{source: source} do
    assert source =~ ~s|setOf("column", "row", "wrap", "text", "icon", "box")|
  end

  test "explicit fill_width false makes boxes intrinsic without changing the default", %{
    source: source
  } do
    assert source =~ ~s|val explicitlyIntrinsic = boolProp(node.props, "fill_width") == false|

    assert source =~
             "if (hasWidth || explicitlyIntrinsic) m else m.fillMaxWidth()"
  end
end
