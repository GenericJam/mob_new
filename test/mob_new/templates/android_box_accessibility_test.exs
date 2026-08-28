defmodule MobNew.Templates.AndroidBoxAccessibilityTest do
  use ExUnit.Case, async: true

  @bridge Path.expand(
            "../../../priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex",
            __DIR__
          )

  test "generated boxes expose labels, action roles, and disabled semantics" do
    source = File.read!(@bridge)

    assert source =~ "val isButton = node.type == \"box\" && accessibilityRole == \"button\""
    assert source =~ "isButton && tapHandle != null ->"
    assert source =~ "clickable(enabled = !isDisabled, role = Role.Button)"

    # Compose publishes disabled() semantics whenever clickable's `enabled` is
    # false, so "no handler" must not be encoded as enabled = false — that
    # announced a live box as disabled.
    refute source =~ "enabled = !isDisabled && tapHandle != null"
    assert source =~ "val accessibilityModifier = Modifier.semantics("
    assert source =~ "mergeDescendants = accessibilityLabel != null"
    assert source =~ "contentDescription = accessibilityLabel"
    assert source =~ "if (isButton) role = Role.Button"
    assert source =~ "if (isDisabled) disabled()"

    # A disabled box must not dispatch regardless of whether it carries an
    # explicit button role. The non-button arm originally had no enabled
    # check, so `disabled: true` without a role announced as disabled to
    # TalkBack and still fired.
    assert source =~
             "modifier.clickable(enabled = !isDisabled) { MobBridge.nativeSendTap(tapHandle) }"

    # Merge on label OR button role, matching iOS. Role without merging leaves
    # children as separate accessibility nodes inside a "button".
    assert source =~ "mergeDescendants = accessibilityLabel != null || isButton"
  end

  test "only boxes with an explicit button role receive button semantics" do
    source = File.read!(@bridge)

    assert source =~ "if (isButton)"
    assert source =~ "tapHandle != null && node.type != \"button\""
  end
end
