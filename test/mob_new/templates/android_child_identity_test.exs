# Template-assertion test: children are keyed by author :id, not position (MOB-127).
# credo:disable-for-this-file Jump.CredoChecks.VacuousTest
defmodule MobNew.Templates.AndroidChildIdentityTest do
  use ExUnit.Case, async: true

  @bridge Path.expand(
            "../../../priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex",
            __DIR__
          )

  setup_all do
    {:ok, src: File.read!(@bridge)}
  end

  defp squish(s), do: s |> String.replace(~r/\s+/, " ") |> String.trim()
  defp has?(hay, needle), do: String.contains?(squish(hay), squish(needle))

  test "the lazy list keys its items", %{src: src} do
    # `items(children)` without a key is index-keyed — the direct equivalent of
    # SwiftUI's `ForEach(id: \\.offset)`. On a LazyColumn it also loses scroll
    # anchoring across an insert.
    refute has?(src, "items(node.children) { child -> RenderNode(child) }")
    assert has?(src, "itemsIndexed(node.children, key = { index, _ -> keys[index] })")
  end

  test "eager column and row children are keyed", %{src: src} do
    # Without key(), an insert shifts every later child into its neighbour's
    # composition slot, so remembered state — a text_field's edit buffer, a
    # scroll position — moves with the position rather than the row.
    assert has?(src, "key(keys[i]) { RenderNode(child, childModifier) }")

    assert length(
             String.split(
               src,
               "val keys = remember(node.children) { mobChildKeys(node.children) }"
             )
           ) - 1 == 3
  end

  test "weight is resolved in the layout scope, not inside key()", %{src: src} do
    # Modifier.weight comes from ColumnScope/RowScope. forEachIndexed is inline
    # so the scope survives, but key()'s block is a plain composable lambda with
    # no scope of its own — computing the modifier inside it would not compile.
    assert has?(src, """
           val w = floatProp(child.props, "weight")
           val childModifier = if (w != null) Modifier.weight(w) else Modifier
           key(keys[i]) { RenderNode(child, childModifier) }
           """)
  end

  test "authored ids and positions cannot collide", %{src: src} do
    body = key_fun(src)
    assert has?(body, ~s|"i\\u0001" + authored|)
    assert has?(body, ~s|"p\\u0001" + index|)
  end

  test "a duplicate id gets its position folded in", %{src: src} do
    # Compose THROWS on duplicate keys in a lazy list, so a repeated author id
    # would turn a cosmetic problem into a crash.
    assert has?(key_fun(src), ~s|if (!seen.add(k)) k = "d\\u0001" + index + "\\u0001" + k|)
  end

  test "keys are plain Strings", %{src: src} do
    # LazyColumn keys must survive saved-instance state, and MobNodeIdentityKey
    # is a data class, not Saveable.
    assert has?(src, "internal fun mobChildKeys(children: List<MobNode>): List<String>")
  end

  test "only a non-empty String id counts, matching iOS", %{src: src} do
    # iOS reads :id as an NSString and ignores anything else. Keying on any JSON
    # value here — which MobNodeIdentity.keyFor does — meant `id: user.id` with
    # an integer keyed rows on Android and fell back to positional on iOS.
    # Mob.Renderer now coerces atoms and numbers to strings, so the two agree by
    # construction; this keeps the Android side from widening again.
    assert has?(
             key_fun(src),
             ~s|val authored = (child.props["id"] as? String)?.takeIf { it.isNotEmpty() }|
           )

    # And deliberately NOT keyFor, which raises on an unknown value type — fine
    # for one sheet per screen, not fine for every child of every list.
    # Comments stripped: the explanation above the line names the thing being
    # refuted, and a test that fails on its own prose is worse than none.
    refute has?(code_only(key_fun(src)), "MobNodeIdentity.keyFor")
  end

  test "the key list is not rebuilt on every recomposition", %{src: src} do
    # canonicalJsonValue builds a String per child; without remember that ran on
    # every recomposition of every Column and Row, where the previous code
    # allocated nothing at all.
    assert length(String.split(src, "remember(node.children) { mobChildKeys(node.children) }")) -
             1 == 3
  end

  # Kotlin source with // comment lines removed.
  defp code_only(src) do
    src
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) |> String.starts_with?("//")))
    |> Enum.join("\n")
  end

  defp key_fun(src) do
    src
    |> String.split("internal fun mobChildKeys(")
    |> Enum.at(1)
    |> String.split("\n}\n", parts: 2)
    |> Enum.at(0)
  end
end
