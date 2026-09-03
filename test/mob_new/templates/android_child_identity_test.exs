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

    # The three that bind `keys` to a local: Column, Row, and the lazy list
    # (hoisted above its LazyColumn, whose builder lambda is not composable).
    # The other four call mobChildKeys inline and are covered by the
    # every-container test below.
    assert length(String.split(src, "val keys = mobChildKeys(node.children)")) - 1 == 3
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

  test "EVERY container keys its children, not just some", %{src: src} do
    # The first version keyed 3 of 7 — column, row and the lazy list — leaving
    # box, both scroll axes and the sheet body positional while iOS keyed all
    # seven. That is MOB-127 itself, unfixed, as a NEW cross-platform
    # divergence: prepend a row inside a sheet and the typed text follows the
    # position on Android and the row on iOS.
    #
    # Asserted as the ABSENCE of the unkeyed form, which is what the earlier
    # presence-only assertions could not see.
    refute has?(src, "node.children.forEach { RenderNode(it) }")
    assert length(String.split(src, "mobChildKeys(node.children)")) - 1 == 7
  end

  test "the key list is not memoised behind a deeper comparison", %{src: src} do
    # remember(node.children) was added when mobChildKeys still called
    # canonicalJsonValue. The same commit replaced that with a String cast plus
    # a concat, leaving a deep structural List<MobNode> compare guarding a
    # shallow one — routinely more work than it saved.
    refute has?(src, "remember(node.children) { mobChildKeys")
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
