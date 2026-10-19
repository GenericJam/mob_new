# Template-assertion test: the generated Android `zoomable: true` image.
# The behaviour lives in Compose gesture code the host suite cannot run, so
# these pin the few lines whose loss would break the contract silently.
defmodule MobNew.Templates.AndroidZoomableImageTest do
  use ExUnit.Case, async: true

  @bridge Application.app_dir(
            :mob_new,
            "priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex"
          )

  setup_all do
    source = File.read!(@bridge)

    %{
      image: source |> region("private fun MobImage(", "\n}\n") |> code_only() |> squish(),
      zoom: source |> region("private fun MobZoomableImage(", "\n}\n") |> code_only() |> squish()
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

  test "zoomable images take the zoom path with the documented defaults and clamps", %{
    image: image
  } do
    assert image =~ ~s|if (boolProp(node.props, "zoomable") == true) {|
    assert image =~ ~s|(floatProp(node.props, "max_zoom") ?: 4f).coerceAtLeast(1f)|
    assert image =~ ~s|(floatProp(node.props, "double_tap_zoom") ?: 2.5f).coerceIn(1f, maxZoom)|
    assert image =~ "MobZoomableImage(model, src, maxZoom, doubleTapZoom, m) return }"

    # The non-zoomable path is still the plain AsyncImage with the author's
    # content scale.
    assert image =~ "contentScale = contentScale,"
  end

  test "zoom resets when src changes", %{zoom: zoom} do
    assert zoom =~ "var scale by remember(src) { mutableStateOf(1f) }"
    assert zoom =~ "var offset by remember(src) { mutableStateOf(Offset.Zero) }"
  end

  test "a one-finger drag is consumed only while zoomed in", %{zoom: zoom} do
    # The contract with a parent scroll or pager: at 1x a one-finger drag
    # must reach the parent. Consuming it unconditionally (or before touch
    # slop) would freeze the pager behind every photo.
    one_finger = region(zoom, "} else if (fingers == 1) {", "upTime =")

    assert one_finger =~
             "if (panning && scale > 1f) { offset = clamp(offset + pan, scale) " <>
               "event.changes.forEach { if (it.positionChanged()) it.consume() } }"

    # Exactly one consume in the one-finger branch: the zoomed-in one.
    assert [_] = :binary.matches(one_finger, ".consume()")

    # Never the down: an on_tap clickable outside the image needs it.
    assert zoom =~ "awaitFirstDown(requireUnconsumed = false)"
    refute zoom =~ "down.consume()"
  end

  test "gestures read the frame untransformed and the zoom is clipped to it", %{zoom: zoom} do
    clip = :binary.match(zoom, ".clipToBounds()") |> elem(0)
    pointer = :binary.match(zoom, ".pointerInput(src, maxZoom, doubleTapZoom)") |> elem(0)
    layer = :binary.match(zoom, ".graphicsLayer {") |> elem(0)

    # pointerInput after graphicsLayer would receive positions in the zoomed
    # space and zoom about the wrong point; clipToBounds after it would not
    # clip the layer.
    assert clip < pointer and pointer < layer
  end

  test "pinch zoom is clamped to 1..maxZoom", %{zoom: zoom} do
    assert zoom =~ "(scale * event.calculateZoom()).coerceIn(1f, maxZoom)"
  end
end
