defmodule MobNew.Templates.AndroidTextMaxLinesTest do
  use ExUnit.Case, async: true

  @bridge Path.expand(
            "../../../priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex",
            __DIR__
          )

  test "a text node caps its lines and ellipsises only when max_lines is set" do
    source = File.read!(@bridge)

    assert source =~ ~s|val maxLines      = intProp(node.props, "max_lines")?.takeIf { it > 0 }|

    # Unset must fall back to Compose's own defaults (Int.MAX_VALUE / Clip),
    # not to some other limit, so an app without the prop renders as before.
    assert source =~ "maxLines      = maxLines ?: Int.MAX_VALUE,"

    assert source =~
             "overflow      = if (maxLines != null) TextOverflow.Ellipsis else TextOverflow.Clip,"
  end
end
