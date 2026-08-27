defmodule MobNew.Templates.AndroidBoxAccessibilityTest do
  use ExUnit.Case, async: true

  @bridge Path.expand(
            "../../../priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex",
            __DIR__
          )

  test "generated boxes expose labels, action roles, and disabled semantics" do
    source = File.read!(@bridge)

    assert source =~ "val isButton = node.type == \"box\" && accessibilityRole == \"button\""
    assert source =~ "clickable(enabled = !isDisabled && tapHandle != null, role = Role.Button)"
    assert source =~ "if (tapHandle != null) MobBridge.nativeSendTap(tapHandle)"
    assert source =~ "val accessibilityModifier = Modifier.semantics("
    assert source =~ "mergeDescendants = accessibilityLabel != null"
    assert source =~ "contentDescription = accessibilityLabel"
    assert source =~ "if (isButton) role = Role.Button"
    assert source =~ "if (isDisabled) disabled()"
  end

  test "only boxes with an explicit button role receive button semantics" do
    source = File.read!(@bridge)

    assert source =~ "if (isButton)"
    assert source =~ "tapHandle != null && node.type != \"button\""
  end
end
