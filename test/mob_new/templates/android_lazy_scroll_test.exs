# Template-assertion test: guards the generated Android `:scroll` lazy path.
# credo:disable-for-this-file Jump.CredoChecks.VacuousTest
defmodule MobNew.Templates.AndroidLazyScrollTest do
  use ExUnit.Case, async: true

  @bridge Path.expand(
            "../../../priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex",
            __DIR__
          )

  setup_all do
    {:ok, source: File.read!(@bridge)}
  end

  test "laziness is opt-in via the scroll node's own lazy prop", %{source: src} do
    # Not the default. Rows below the fold are never composed, so they never
    # register a frame and Mob.Test.element_frames / tap_id cannot address them,
    # and scroll position becomes index-based. An app must ask for that.
    assert src =~ ~s|boolProp(node.props, "lazy") == true|
  end

  test "flattening drops only props a LazyColumn already provides", %{source: src} do
    # Widening this set silently discards whatever the column contributed:
    # padding, background, align, an id the harness addresses, a tap handler.
    assert src =~ ~s/sole.props.keys.all { it == "fill_width"/
    assert src =~ ~s/it == "fill_height" }/
  end

  test "a child carrying weight forces the eager path", %{source: src} do
    # weight comes from ColumnScope. LazyColumn items have no such scope, so a
    # flattened child's weight would be dropped without a trace.
    assert src =~ ~s|sole.children.none { it.props.containsKey("weight") }|
  end

  test "the lazy path clears the pixel ScrollState it never attaches", %{source: src} do
    # scrollInfo checks scrollState BEFORE lazyState. A ScrollState that was
    # never attached to a verticalScroll keeps maxValue == Int.MAX_VALUE, so
    # leaving it registered makes scroll_to return :ok without moving and
    # screenshot_tour page roughly a million times.
    lazy_branch =
      src
      |> String.split("if (flattenable) {")
      |> Enum.at(1)
      |> String.split("} else {")
      |> Enum.at(0)

    assert lazy_branch =~ "handle.scrollState = null"
  end

  test "a fill_height scroll child is not force-weighted in its parent column", %{source: src} do
    # An earlier version gave it Modifier.weight(1f) on the theory that Column
    # measures non-weighted children unbounded. That is false — Column measures
    # them against the remaining space — and the weight both zeroed the child
    # inside an unbounded Column and changed weight distribution for apps that
    # never touched the lazy path.
    refute src =~ "fillsHeight -> Modifier.weight(1f)"
  end
end
