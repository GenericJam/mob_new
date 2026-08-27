defmodule MobNew.Templates.AndroidContentSheetTest do
  use ExUnit.Case, async: true

  @bridge Path.expand(
            "../../../priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex",
            __DIR__
          )

  test "Compose sheet preserves built-ins and recognizes encoded content detents" do
    source = File.read!(@bridge)

    assert source =~ ~S|detent.optString("type") == "content"|
    assert source =~ "val contentOnly = contentDetent != null"
    assert source =~ "skipPartiallyExpanded = !allowsMedium"
    assert source =~ "allowsLarge || value != SheetValue.Expanded"
  end

  test "content sheet wraps naturally, caps height, and scrolls overflow" do
    source = File.read!(@bridge)

    assert source =~ ~S|detent.has("max_height")|
    assert source =~ ~S|?.optDouble("max_height")|
    assert source =~ "let(maxHeight::coerceAtMost)"
    assert source =~ "heightIn(max = contentMaximumHeight)"
    assert source =~ "verticalScroll(rememberScrollState())"
  end
end
