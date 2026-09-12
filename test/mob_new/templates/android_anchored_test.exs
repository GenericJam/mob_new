defmodule MobNew.Templates.AndroidAnchoredTest do
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

  setup_all do
    source = File.read!(@bridge)
    %{source: source, code: source |> code_only() |> squish()}
  end

  test "the dispatch table routes :anchored to MobAnchored", %{code: code} do
    assert code =~ ~s|"anchored" -> MobAnchored(node, m)|
  end

  test "the panel renders in its own window, not in flow", %{source: source} do
    body = source |> region("private fun MobAnchored", "private fun rememberRealDisplaySizePx")
    code = body |> code_only() |> squish()

    assert code =~ "Popup( popupPositionProvider = provider,"
    # The window manager must NOT pin the popup on screen: the position
    # provider clamps instead, and only while the anchor is visible.
    assert code =~ "clippingEnabled = false,"
    # on_tap on the node is the outside-tap dismiss request.
    assert code =~ ~s|val dismiss = intProp(node.props, "on_tap")|
    assert code =~ "onDismissRequest = dismiss?.let { { MobBridge.nativeSendTap(it) } },"
    assert code =~ "dismissOnClickOutside = dismiss != null,"
    # The panel is capped so a fill_width panel cannot go screen-wide.
    assert code =~ "Box(modifier = Modifier.widthIn(max = maxW).heightIn(max = maxH))"
  end

  test "the position provider carries the shared arithmetic", %{source: source} do
    body = source |> region("private class MobAnchoredPositionProvider", "private fun MobText")
    code = body |> code_only() |> squish()

    assert code =~ ": PopupPositionProvider {"
    # The align_offset sign flips on "end": a positive offset pushes inward.
    assert code =~ ~s|"end" -> anchorBounds.right - pw - alOff|
    assert code =~ ~s|"end" -> anchorBounds.bottom - ph - alOff|
    # Clamp is gated on the anchor being on the real display.
    assert code =~ "if (clamp && anchorOnScreen) {"
    assert code =~ "x = x.coerceIn(padLeft, maxOf(padLeft, vw - pw - padRight))"
    assert code =~ "y = y.coerceIn(padTop, maxOf(padTop, vh - ph - padBottom))"
  end

  test "a clickable wrapper never swallows the trigger's tap", %{source: source} do
    body = source |> region("private fun RenderNodeInner", "private fun MobText")
    code = body |> code_only() |> squish()

    assert code =~
             ~s|tapHandle != null && node.type != "button" && node.type != "anchored" -> modifier.clickable(enabled = !isDisabled)|
  end

  test "the Popup imports are present exactly once", %{source: source} do
    for import <- [
          "import androidx.compose.ui.window.Popup",
          "import androidx.compose.ui.window.PopupPositionProvider",
          "import androidx.compose.ui.window.PopupProperties",
          "import androidx.compose.ui.unit.IntOffset",
          "import androidx.compose.ui.unit.IntRect",
          "import androidx.compose.ui.unit.IntSize",
          "import androidx.compose.ui.unit.LayoutDirection",
          "import androidx.compose.ui.platform.LocalConfiguration",
          "import androidx.compose.ui.platform.LocalLayoutDirection",
          "import androidx.compose.foundation.layout.safeDrawing",
          "import androidx.compose.foundation.layout.widthIn"
        ] do
      assert length(String.split(source, import <> "\n")) == 2, "#{import} missing or duplicated"
    end

    # android.view.WindowInsets is already imported for the decor-view inset
    # reads, so the Compose one must come in under an alias or the two clash.
    assert source =~
             "import androidx.compose.foundation.layout.WindowInsets as ComposeWindowInsets"

    assert source =~ "ComposeWindowInsets.safeDrawing"
  end
end
