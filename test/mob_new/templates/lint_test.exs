defmodule MobNew.Templates.LintTest do
  use ExUnit.Case, async: true

  alias MobNew.Templates.Lint

  describe "balanced_braces/1" do
    test "passes on balanced output" do
      assert Lint.balanced_braces("fun foo() { return { a: 1 } }") == []
    end

    test "flags missing closing brace" do
      [issue] = Lint.balanced_braces("fun foo() { return { 1 }")
      assert issue.kind == :balanced_braces
      assert issue.message =~ "2 `{` vs 1 `}`"
    end

    test "flags extra opening brace" do
      [issue] = Lint.balanced_braces("fun foo() { { return 1 }")
      assert issue.kind == :balanced_braces
    end

    test "handles empty content" do
      assert Lint.balanced_braces("") == []
    end
  end

  describe "balanced_parens/1" do
    test "passes on balanced output" do
      assert Lint.balanced_parens("foo(bar(baz()))") == []
    end

    test "flags missing close paren" do
      [issue] = Lint.balanced_parens("foo(bar(baz)")
      assert issue.kind == :balanced_parens
    end
  end

  describe "balanced_brackets/1" do
    test "passes on balanced output" do
      assert Lint.balanced_brackets("[1, [2, 3], [4]]") == []
    end

    test "flags unbalanced brackets" do
      [issue] = Lint.balanced_brackets("[1, [2, 3]")
      assert issue.kind == :balanced_brackets
    end
  end

  describe "no_eex_leaks/1" do
    test "passes when no EEx tags remain" do
      assert Lint.no_eex_leaks("class Foo { val x = 1 }") == []
    end

    test "flags leaked `<%=` opening tag" do
      issues = Lint.no_eex_leaks("val name = <%= @name %>")
      assert Enum.any?(issues, &(&1.kind == :eex_open_eq))
      assert Enum.any?(issues, &(&1.kind == :eex_close))
    end

    test "flags leaked `<% ` non-output tag" do
      issues = Lint.no_eex_leaks("<% if true do %>")
      assert Enum.any?(issues, &(&1.kind == :eex_open))
    end

    test "doesn't false-positive on Kotlin generics or shift operators" do
      # `<%` is the leading EEx token but `<x %>` isn't actually EEx-y in
      # any way we'd see in normal Kotlin. Bitwise shifts (`<<`, `>>`)
      # and generics (`Foo<Bar>`) don't trigger any pattern.
      assert Lint.no_eex_leaks("class Foo<Bar> { val x = 1 shl 2 }") == []
    end
  end

  describe "unique_kotlin_imports/1" do
    test "passes on unique imports" do
      content = """
      import android.os.Bundle
      import android.util.Log
      import java.util.UUID
      """

      assert Lint.unique_kotlin_imports(content) == []
    end

    test "flags single duplicate" do
      content = """
      import android.os.Bundle
      import android.util.Log
      import android.os.Bundle
      """

      [issue] = Lint.unique_kotlin_imports(content)
      assert issue.kind == :duplicate_kotlin_import
      assert issue.message =~ "android.os.Bundle"
      assert issue.message =~ "2 times"
    end

    test "flags multiple distinct duplicates" do
      content = """
      import a.b.X
      import c.d.Y
      import a.b.X
      import c.d.Y
      """

      issues = Lint.unique_kotlin_imports(content)
      assert length(issues) == 2
      assert Enum.all?(issues, &(&1.kind == :duplicate_kotlin_import))
    end

    test "tolerates whitespace around imports" do
      # Real Kotlin output sometimes has trailing whitespace; the
      # check should normalise before comparing.
      content = "import x.y.Z  \nimport x.y.Z"
      [_issue] = Lint.unique_kotlin_imports(content)
    end
  end

  describe "unique_swift_imports/1" do
    test "passes on unique imports" do
      assert Lint.unique_swift_imports("import Foundation\nimport SwiftUI") == []
    end

    test "flags Swift duplicates" do
      content = "import Foundation\nimport SwiftUI\nimport Foundation"
      [issue] = Lint.unique_swift_imports(content)
      assert issue.kind == :duplicate_swift_import
    end
  end

  describe "external_fun_jni_consistency/2" do
    test "passes when Kotlin externs match C JNI thunks" do
      kt = """
      @JvmStatic external fun nativeFoo(pid: Long)
      @JvmStatic external fun nativeBar(pid: Long, x: Int)
      """

      c = """
      JNIEXPORT void JNICALL Java_com_example_app_MobBridge_nativeFoo(JNIEnv* env, jclass cls, jlong pid) {}
      JNIEXPORT void JNICALL Java_com_example_app_MobBridge_nativeBar(JNIEnv* env, jclass cls, jlong pid, jint x) {}
      """

      assert Lint.external_fun_jni_consistency(kt, c) == []
    end

    test "flags Kotlin extern with no matching C thunk" do
      kt = "@JvmStatic external fun nativeMissingInC(pid: Long)"
      c = ""
      [issue] = Lint.external_fun_jni_consistency(kt, c)
      assert issue.kind == :missing_jni_thunk
      assert issue.message =~ "nativeMissingInC"
    end

    test "flags C thunk with no matching Kotlin extern" do
      kt = ""

      c =
        "JNIEXPORT void JNICALL Java_com_example_app_MobBridge_nativeOrphan(JNIEnv* env, jclass cls) {}"

      [issue] = Lint.external_fun_jni_consistency(kt, c)
      assert issue.kind == :missing_kotlin_extern
      assert issue.message =~ "nativeOrphan"
    end

    test "tolerates different Java packages between the two files" do
      # The infix `_com_example_app_MobBridge_` is package-dependent;
      # the check should only compare the `native...` suffix.
      kt = "@JvmStatic external fun nativeFoo(pid: Long)"
      c = "JNIEXPORT void JNICALL Java_org_other_pkg_MobBridge_nativeFoo() {}"
      assert Lint.external_fun_jni_consistency(kt, c) == []
    end
  end

  describe "native_funs_owned_by_mob_bridge/1 (MOB-98)" do
    test "passes when every native fun lives inside object MobBridge" do
      kt = """
      object MobBridge {
          @JvmStatic external fun nativeFoo(pid: Long)
          @JvmStatic external fun nativeDeliverComponentEvent(handle: Int, event: String, payloadJson: String)
      }

      object MobNativeViewRegistry {
          fun render(node: MobNode) {}
      }
      """

      assert Lint.native_funs_owned_by_mob_bridge(kt) == []
    end

    test "flags a native fun declared on a different object (the exact MOB-98 shape)" do
      kt = """
      object MobBridge {
          @JvmStatic external fun nativeFoo(pid: Long)
      }

      object MobNativeViewRegistry {
          external fun nativeDeliverComponentEvent(handle: Int, event: String, payloadJson: String)
      }
      """

      [issue] = Lint.native_funs_owned_by_mob_bridge(kt)
      assert issue.kind == :native_fun_outside_mob_bridge
      assert issue.message =~ "nativeDeliverComponentEvent"
    end

    test "a native fun declared before object MobBridge is also flagged" do
      kt = """
      external fun nativeOrphan(pid: Long)

      object MobBridge {
          @JvmStatic external fun nativeFoo(pid: Long)
      }
      """

      [issue] = Lint.native_funs_owned_by_mob_bridge(kt)
      assert issue.message =~ "nativeOrphan"
    end

    test "returns no issues (nothing to check) when there's no object MobBridge at all" do
      kt = "external fun nativeOrphan(pid: Long)"
      assert Lint.native_funs_owned_by_mob_bridge(kt) == []
    end

    test "handles a MobBridge body containing nested braces" do
      kt = """
      object MobBridge {
          fun helper() {
              if (true) { doSomething() }
          }
          @JvmStatic external fun nativeFoo(pid: Long)
      }
      """

      assert Lint.native_funs_owned_by_mob_bridge(kt) == []
    end

    test "flags a native fun nested inside another class within object MobBridge" do
      # Byte-position alone would call this "inside object MobBridge" — it
      # is, but not as a DIRECT member. JNI would need MobBridge$Helper as
      # the declaring class, not MobBridge, so the generated Java_..._MobBridge_
      # thunk would still mismatch.
      kt = """
      object MobBridge {
          @JvmStatic external fun nativeFoo(pid: Long)

          class Helper {
              external fun nativeNested(pid: Long)
          }
      }
      """

      [issue] = Lint.native_funs_owned_by_mob_bridge(kt)
      assert issue.message =~ "nativeNested"
      assert issue.message =~ "not a direct member"
    end
  end

  describe "jvm_static_fun_owned_by_mob_bridge?/2" do
    test "accepts a direct @JvmStatic function" do
      kt = """
      object MobBridge {
          @JvmStatic
          fun screenInfo(): FloatArray = FloatArray(7)
      }
      """

      assert Lint.jvm_static_fun_owned_by_mob_bridge?(kt, "screenInfo")
    end

    test "rejects an absent, nested, or differently-owned function" do
      absent = "object MobBridge {}"

      nested = """
      object MobBridge {
          object Helper {
              @JvmStatic fun screenInfo(): FloatArray = FloatArray(7)
          }
      }
      """

      other_owner = """
      object MobBridge {}
      object Helper {
          @JvmStatic fun screenInfo(): FloatArray = FloatArray(7)
      }
      """

      refute Lint.jvm_static_fun_owned_by_mob_bridge?(absent, "screenInfo")
      refute Lint.jvm_static_fun_owned_by_mob_bridge?(nested, "screenInfo")
      refute Lint.jvm_static_fun_owned_by_mob_bridge?(other_owner, "screenInfo")
    end
  end

  describe "sheet_content_modifier_not_double_applied/1" do
    test "passes on the correct shape — dispatch calls MobSheet(node), body strips the two keys" do
      kt = """
      when (node.type) {
          "sheet"          -> MobSheet(node)
      }

      private fun MobSheet(node: MobNode) {
          val contentProps = node.props - listOf("background", "corner_radius")
          val contentModifier = nodeModifier(contentProps)
      }
      """

      assert Lint.sheet_content_modifier_not_double_applied(kt) == []
    end

    test "flags the dispatch arm passing the raw m modifier through" do
      kt = """
      when (node.type) {
          "sheet"          -> MobSheet(node, m)
      }

      private fun MobSheet(node: MobNode) {
          val contentProps = node.props - listOf("background", "corner_radius")
      }
      """

      issues = Lint.sheet_content_modifier_not_double_applied(kt)

      assert Enum.any?(
               issues,
               &(&1.kind == :sheet_modifier_double_applied and &1.message =~ "dispatch arm")
             )
    end

    test "flags MobSheet building its content modifier from unstripped node.props" do
      kt = """
      when (node.type) {
          "sheet"          -> MobSheet(node)
      }

      private fun MobSheet(node: MobNode) {
          val contentModifier = nodeModifier(node.props)
      }
      """

      issues = Lint.sheet_content_modifier_not_double_applied(kt)

      assert Enum.any?(
               issues,
               &(&1.kind == :sheet_modifier_double_applied and &1.message =~ "strip")
             )
    end

    test "returns no issues when there's no MobSheet function at all" do
      kt = "private fun MobButton(node: MobNode, modifier: Modifier) {}"
      assert Lint.sheet_content_modifier_not_double_applied(kt) == []
    end

    test "accepts the keys stripped in either order" do
      kt = """
      "sheet"          -> MobSheet(node)

      private fun MobSheet(node: MobNode) {
          val contentProps = node.props - listOf("corner_radius", "background")
      }
      """

      assert Lint.sheet_content_modifier_not_double_applied(kt) == []
    end
  end

  describe "check_kotlin/1 aggregate" do
    test "returns empty list on clean Kotlin" do
      content = """
      package com.example.app

      import android.os.Bundle
      import android.util.Log

      class Foo {
        fun bar(x: Int): Int { return x + 1 }
      }
      """

      assert Lint.check_kotlin(content) == []
    end

    test "surfaces multiple issue kinds in one call" do
      content = """
      import x.y.Z
      import x.y.Z
      class Foo { fun bar() { return
      """

      issues = Lint.check_kotlin(content)
      kinds = Enum.map(issues, & &1.kind) |> Enum.uniq() |> Enum.sort()
      assert :balanced_braces in kinds
      assert :duplicate_kotlin_import in kinds
    end
  end

  describe "check_c/1 aggregate" do
    test "returns empty list on clean C" do
      content = """
      #include <stdio.h>

      void foo(int x) {
          printf("%d\\n", x);
      }
      """

      assert Lint.check_c(content) == []
    end
  end
end
