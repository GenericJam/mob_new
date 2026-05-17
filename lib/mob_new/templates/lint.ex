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
      &unique_kotlin_imports/1
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
