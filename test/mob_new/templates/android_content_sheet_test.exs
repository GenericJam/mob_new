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

  test "a content sheet does not nest its own scroll around a scrollable child" do
    source = File.read!(@bridge)

    # Compose THROWS when a scrollable is measured with an infinite max height,
    # so wrapping verticalScroll around a `scroll`/`lazy_list` child crashed the
    # app at first measure. The cap still applies; the child owns the scrolling.
    assert source =~ "val hasScrollableChild = node.children.any(::isScrollableNode)"
    assert source =~ "contentOnly && hasScrollableChild ->"
    assert source =~ "node.type == \"scroll\""
    assert source =~ "node.type == \"lazy_list\""

    # The height cap must sit inside the node's own padding, or padding is
    # added outside max_height and overshoots the documented cap.
    detent_at = :binary.match(source, ".then(contentDetentModifier)") |> elem(0)
    padding_at = :binary.match(source, ".then(contentModifier)") |> elem(0)
    assert detent_at < padding_at, "height cap must be applied before the node's padding"
  end
end
