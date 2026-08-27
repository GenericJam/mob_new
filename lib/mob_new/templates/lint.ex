defmodule MobNew.Templates.Lint do
  @moduledoc """
  Structural lints for generator-rendered native source files.

  EEx templates can produce output that string-match generator tests
  miss — duplicate imports, missing braces, orphan `<%=` tags. Real
  compilation would catch them but is expensive (needs Android SDK
  for Kotlin, Xcode for Swift, etc.). These lints are the cheap
  middle layer: language-agnostic structural checks that run in
  sub-second time on every `mix test`.

  Each check returns a list of `issue` maps; the empty list means
  no problems. Aggregate functions (`check_kotlin/1`, `check_c/1`,
  `check_swift/1`) run all checks relevant to a language and return
  the combined issue list.

  Use:

      content = File.read!("path/to/MobBridge.kt")
      assert MobNew.Templates.Lint.check_kotlin(content) == []

  Or for finer-grained reporting:

      content
      |> MobNew.Templates.Lint.check_kotlin()
      |> Enum.each(&IO.puts(&1.message))

  Limits: structural only. A typo that produces still-balanced
  braces (`x_funtion` instead of `x_function`) won't be caught.
  See `mix mob.lint_templates` (planned) for a fuller battery that
  also invokes `zig cc -fsyntax-only` on rendered C.
  """

  @type issue :: %{
          required(:kind) => atom(),
          required(:message) => String.t()
        }

  # ── Public per-language aggregate checks ─────────────────────────────────

  @doc """
  Runs all Kotlin-relevant checks on the given content. Returns
  combined issue list (empty = clean).
  """
  @spec check_kotlin(String.t()) :: [issue()]
  def check_kotlin(content) do
    [
      &balanced_braces/1,
      &balanced_parens/1,
      &balanced_brackets/1,
      &no_eex_leaks/1,
      &unique_kotlin_imports/1,
      &native_funs_owned_by_mob_bridge/1,
      &sheet_content_modifier_not_double_applied/1
    ]
    |> Enum.flat_map(& &1.(content))
  end

  @doc """
  Runs all C-relevant checks on the given content. Returns
  combined issue list.
  """
  @spec check_c(String.t()) :: [issue()]
  def check_c(content) do
    [
      &balanced_braces/1,
      &balanced_parens/1,
      &no_eex_leaks/1
    ]
    |> Enum.flat_map(& &1.(content))
  end

  @doc """
  Runs all Swift-relevant checks on the given content.
  """
  @spec check_swift(String.t()) :: [issue()]
  def check_swift(content) do
    [
      &balanced_braces/1,
      &balanced_parens/1,
      &no_eex_leaks/1,
      &unique_swift_imports/1
    ]
    |> Enum.flat_map(& &1.(content))
  end

  # ── Individual checks (each is `:ok` or `[issue, ...]`) ──────────────────

  @doc """
  Asserts equal counts of `{` and `}`. Naive — strings containing
  literal braces would skew the count, but template C/Kotlin/Swift
  output rarely has JSON or `printf("{...}")` strings.
  """
  @spec balanced_braces(String.t()) :: [issue()]
  def balanced_braces(content), do: balanced(content, ?{, ?}, :balanced_braces)

  @doc "Asserts equal counts of `(` and `)`."
  @spec balanced_parens(String.t()) :: [issue()]
  def balanced_parens(content), do: balanced(content, ?(, ?), :balanced_parens)

  @doc "Asserts equal counts of `[` and `]`."
  @spec balanced_brackets(String.t()) :: [issue()]
  def balanced_brackets(content), do: balanced(content, ?[, ?], :balanced_brackets)

  @doc """
  Catches `<%=` / `<%` / `%>` left in rendered output. Indicates a
  malformed template tag or a render-pipeline misconfiguration that
  emitted the literal text instead of evaluating it.
  """
  @spec no_eex_leaks(String.t()) :: [issue()]
  def no_eex_leaks(content) do
    [{"<%=", :eex_open_eq}, {"<% ", :eex_open}, {" %>", :eex_close}]
    |> Enum.filter(fn {pattern, _} -> String.contains?(content, pattern) end)
    |> Enum.map(fn {pattern, kind} ->
      %{
        kind: kind,
        message:
          "Rendered output still contains `#{pattern}` — likely a malformed EEx tag in the template"
      }
    end)
  end

  @doc """
  Asserts every `^import ` line in Kotlin output is unique. kotlinc
  rejects duplicate imports with "Conflicting import" and the build
  fails. This was the bug class that hit 0.3.2 → 0.3.4 twice.
  """
  @spec unique_kotlin_imports(String.t()) :: [issue()]
  def unique_kotlin_imports(content) do
    duplicate_imports(content, "import ", :duplicate_kotlin_import)
  end

  @doc """
  Asserts every `^import ` line in Swift output is unique. swiftc
  is more forgiving than kotlinc (warns rather than errors on
  duplicates) but Apple's archive-validation pass surfaces them.
  """
  @spec unique_swift_imports(String.t()) :: [issue()]
  def unique_swift_imports(content) do
    duplicate_imports(content, "import ", :duplicate_swift_import)
  end

  @doc """
  For Kotlin/C native bridges: every `external fun nativeFoo(...)`
  declared in the Kotlin file must have a matching
  `Java_..._MobBridge_nativeFoo` JNI thunk in the C file. Catches
  the "added the Kotlin extern but forgot the C side" regression
  (or vice versa). Pass both file contents.

  The Java-class infix between `Java_` and `_native...` is
  package-dependent; we just check the suffix matches.
  """
  @spec external_fun_jni_consistency(String.t(), String.t()) :: [issue()]
  def external_fun_jni_consistency(kotlin_content, c_content) do
    # `@JvmStatic` is optional — Kotlin's `object MobBridge` makes every
    # `external fun` callable from JNI; `@JvmStatic` only affects Java's
    # caller-side syntax, not the JNI dispatch surface.
    kotlin_externs =
      ~r/^\s*(?:@JvmStatic\s+)?external\s+fun\s+(native\w+)/m
      |> Regex.scan(kotlin_content, capture: :all_but_first)
      |> List.flatten()
      |> MapSet.new()

    c_thunks =
      ~r/Java_[\w_]+_MobBridge_(native\w+)\(/
      |> Regex.scan(c_content, capture: :all_but_first)
      |> List.flatten()
      |> MapSet.new()

    missing_in_c =
      kotlin_externs |> MapSet.difference(c_thunks) |> MapSet.to_list() |> Enum.sort()

    missing_in_kt =
      c_thunks |> MapSet.difference(kotlin_externs) |> MapSet.to_list() |> Enum.sort()

    [
      for name <- missing_in_c do
        %{
          kind: :missing_jni_thunk,
          message: "Kotlin declares `external fun #{name}` but C has no matching JNI thunk"
        }
      end,
      for name <- missing_in_kt do
        %{
          kind: :missing_kotlin_extern,
          message:
            "C exports `Java_..._MobBridge_#{name}` but Kotlin has no matching `external fun`"
        }
      end
    ]
    |> List.flatten()
  end

  @doc """
  Every `external fun nativeFoo` in MobBridge.kt must be a *direct*
  member of `object MobBridge` — not just positionally somewhere inside
  its braces, and not just present somewhere in the file.

  `external_fun_jni_consistency/2` above only checks that Kotlin and C
  agree on the native function's NAME; it can't tell which enclosing
  class/object actually owns the Kotlin declaration. JNI resolves a
  native method by its declaring class, and every generated JNI thunk
  in this template is `Java_<pkg>_MobBridge_nativeFoo` — so a
  `nativeFoo` declared on some OTHER object (e.g. a helper registry)
  passes the name-consistency check cleanly and then throws
  `UnsatisfiedLinkError` the first time it's actually called. This is
  the check that would have caught MOB-98's JNI owner mismatch. Only
  meaningful against MobBridge.kt's content — returns `[]` (nothing to
  flag) if the content has no `object MobBridge` block at all.

  Brace-depth aware, not just byte-position aware: `external fun bar`
  inside a hypothetical `object MobBridge { class Foo { external fun
  bar() } }` sits at byte-position inside the span but is NOT a direct
  member — JNI would need `MobBridge$Foo`, not `MobBridge`. Flagged the
  same as if it were outside the span entirely.
  """
  @spec native_funs_owned_by_mob_bridge(String.t()) :: [issue()]
  def native_funs_owned_by_mob_bridge(kotlin_content) do
    case mob_bridge_span(kotlin_content) do
      nil ->
        []

      {open, close} ->
        ~r/external\s+fun\s+(native\w+)/
        |> Regex.scan(kotlin_content, return: :index)
        |> Enum.reject(fn [{whole_at, _} | _] ->
          whole_at >= open and whole_at < close and
            brace_depth_between(kotlin_content, open + 1, whole_at) == 0
        end)
        |> Enum.map(fn [_, {name_at, name_len}] ->
          name = binary_part(kotlin_content, name_at, name_len)

          %{
            kind: :native_fun_outside_mob_bridge,
            message:
              "`external fun #{name}` is not a direct member of `object MobBridge` " <>
                "(nested inside another class/object, or outside it entirely) — every " <>
                "generated JNI thunk is Java_..._MobBridge_#{name}, and JNI resolves a " <>
                "native method by its declaring class"
          }
        end)
    end
  end

  @doc """
  `RenderNodeInner`'s `when (node.type)` dispatch computes `m` =
  `tapModifier.then(nodeModifier(node.props))` BEFORE the dispatch runs —
  `nodeModifier` bakes `background`/`corner_radius` into `m` as
  `.background()`/`.clip()` for every node type uniformly. Most composables
  just apply that `m` and move on. `MobSheet` can't: Material 3
  `ModalBottomSheet` takes `containerColor`/`shape` as constructor
  parameters, the same way `Button` takes `ButtonDefaults.buttonColors`/
  `shape` — those don't compose via a `Modifier` chain, so if MobSheet's
  content also received the pre-baked `m` (or built its own modifier
  straight from `node.props` without stripping those two keys), the
  background would paint twice and the corners would clip twice: once
  from the outer modifier's full-rect rounding, once from
  ModalBottomSheet's own top-corners-only shape.

  Two structural invariants, checked directly against the rendered source
  (not a live composition — this can't catch a visual regression, only
  the textual shape that causes one):

  1. The `"sheet" -> MobSheet(...)` dispatch arm must not pass the
     `m`-derived modifier through.
  2. `MobSheet`'s body must build its content modifier from a props map
     with `"background"`/`"corner_radius"` stripped, not raw `node.props`.

  Returns `[]` if the content has no `MobSheet` function at all (nothing
  to check — e.g. C/Swift content passed by mistake, or a future template
  restructuring that removes the "sheet" node type entirely).
  """
  @spec sheet_content_modifier_not_double_applied(String.t()) :: [issue()]
  def sheet_content_modifier_not_double_applied(kotlin_content) do
    case function_span(kotlin_content, "MobSheet") do
      nil ->
        []

      {open, close} ->
        dispatch_issue(kotlin_content) ++ strip_issue(kotlin_content, open, close)
    end
  end

  defp dispatch_issue(content) do
    if Regex.match?(~r/"sheet"\s*->\s*MobSheet\(\s*node\s*,\s*m\s*\)/, content) do
      [
        %{
          kind: :sheet_modifier_double_applied,
          message:
            "\"sheet\" dispatch arm passes the raw nodeModifier-derived `m` to MobSheet — " <>
              "it already has background/corner_radius baked in as .background()/.clip(), " <>
              "which double-applies against ModalBottomSheet's own containerColor/shape. " <>
              "Call MobSheet(node) without threading `m` through."
        }
      ]
    else
      []
    end
  end

  defp strip_issue(content, open, close) do
    body = binary_part(content, open, close - open)

    stripped? =
      String.contains?(body, ~s[- listOf("background", "corner_radius")]) or
        String.contains?(body, ~s[- listOf("corner_radius", "background")])

    if stripped? do
      []
    else
      [
        %{
          kind: :sheet_modifier_double_applied,
          message:
            "MobSheet doesn't appear to strip background/corner_radius out of the " <>
              "props map before building its content modifier — those belong to " <>
              "ModalBottomSheet's own containerColor/shape params, not the child content"
        }
      ]
    end
  end

  # Byte-offset span of a top-level `private fun <name>(...) { ... }`'s
  # body, `{brace_at, matching_close_at}` — or nil if no such function
  # exists in the content. Generic version of mob_bridge_span/1 below,
  # for any named function rather than specifically `object MobBridge`.
  defp function_span(content, fun_name) do
    with {fun_at, fun_len} <- binary_match(content, "fun #{fun_name}("),
         search_from = fun_at + fun_len,
         {brace_at, _} <- binary_match(content, "{", search_from),
         close_at when not is_nil(close_at) <- matching_brace_index(content, brace_at) do
      {brace_at, close_at}
    else
      _ -> nil
    end
  end

  # Net brace depth opened between byte offsets `from` (inclusive) and `to`
  # (exclusive). 0 at `to` means nothing between them opened an unclosed
  # brace — i.e. `to` is a direct child of whatever `from` is inside, not
  # nested inside some other type declared in between.
  defp brace_depth_between(content, from, to) do
    Enum.reduce(from..(to - 1)//1, 0, fn i, depth ->
      case :binary.at(content, i) do
        ?{ -> depth + 1
        ?} -> depth - 1
        _ -> depth
      end
    end)
  end

  # Byte-offset span of `object MobBridge { ... }`'s body, `{brace_at,
  # matching_close_at}` — or nil if the content has no such block.
  defp mob_bridge_span(content) do
    with {obj_at, obj_len} <- binary_match(content, "object MobBridge"),
         search_from = obj_at + obj_len,
         {brace_at, _} <- binary_match(content, "{", search_from),
         close_at when not is_nil(close_at) <- matching_brace_index(content, brace_at) do
      {brace_at, close_at}
    else
      _ -> nil
    end
  end

  defp binary_match(content, pattern, from \\ 0) do
    case :binary.match(content, pattern, scope: {from, byte_size(content) - from}) do
      :nomatch -> :nomatch
      result -> result
    end
  end

  # Byte offset of the `}` that closes the `{` at `open_index`, or nil if
  # unbalanced. Plain byte scan — safe even with multi-byte UTF-8 elsewhere
  # in the file, since a continuation byte never equals ASCII `{`/`}`.
  defp matching_brace_index(content, open_index) do
    find_matching_brace(content, open_index + 1, 1)
  end

  defp find_matching_brace(content, index, depth) when index < byte_size(content) do
    case :binary.at(content, index) do
      ?{ -> find_matching_brace(content, index + 1, depth + 1)
      ?} when depth == 1 -> index
      ?} -> find_matching_brace(content, index + 1, depth - 1)
      _ -> find_matching_brace(content, index + 1, depth)
    end
  end

  defp find_matching_brace(_content, _index, _depth), do: nil

  # ── helpers ──────────────────────────────────────────────────────────────

  defp balanced(content, open, close, kind) do
    chars = String.to_charlist(content)
    opens = Enum.count(chars, &(&1 == open))
    closes = Enum.count(chars, &(&1 == close))

    if opens == closes do
      []
    else
      [
        %{
          kind: kind,
          message:
            "Unbalanced #{[open]}#{[close]}: #{opens} `#{[open]}` vs #{closes} `#{[close]}` — " <>
              "likely a missing #{[close]} (or extra #{[open]}). Check recent template edits."
        }
      ]
    end
  end

  defp duplicate_imports(content, prefix, kind) do
    duplicates =
      content
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&String.starts_with?(&1, prefix))
      |> Enum.frequencies()
      |> Enum.filter(fn {_, count} -> count > 1 end)
      |> Enum.map(fn {imp, count} -> {imp, count} end)

    for {imp, count} <- duplicates do
      %{
        kind: kind,
        message: "Duplicate import: `#{imp}` appears #{count} times"
      }
    end
  end
end
