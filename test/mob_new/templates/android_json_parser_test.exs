# Template-assertion test: guards the generated Android JSON parser wiring.
# credo:disable-for-this-file Jump.CredoChecks.VacuousTest
defmodule MobNew.Templates.AndroidJsonParserTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../../priv/templates/mob.new/android/app/src", __DIR__)
  @bridge Path.join(@root, "main/java/MobBridge.kt.eex")
  @parser Path.join(@root, "main/java/MobJson.kt.eex")
  @parser_test Path.join(@root, "test/java/MobJsonTest.kt.eex")

  test "setRootJson parses through MobJson, not org.json" do
    src = File.read!(@bridge)
    assert src =~ "MobJson.parseNode(json)"
    refute src =~ "JSONObject(json).toMobNode()"
  end

  test "nested prop values are still built as org.json containers" do
    # MobBridge branches on `is JSONArray` / `is JSONObject` for tabs, uniforms,
    # detents and the throttle configs. A parser that produced its own container
    # type would make those branches fall through and the props would silently
    # stop working — no crash, just a screen that quietly loses behaviour.
    src = File.read!(@parser)
    assert src =~ "private fun readJsonObject(): JSONObject"
    assert src =~ "private fun readJsonArray(): JSONArray"
  end

  test "a JSON null in props keeps org.json's NULL sentinel" do
    # toMobNode stored whatever JSONObject.get returned, which for a JSON null
    # is the sentinel, not a Kotlin null. They compare equal, so `== null` reads
    # the same either way — but `?.let` runs for one and not the other.
    src = File.read!(@parser)
    assert src =~ "m[key] = readValue() ?: JSONObject.NULL"
  end

  test "the parser ships with tests that compare it against the old path" do
    src = File.read!(@parser_test)
    assert src =~ "JSONObject(json).toMobNode()"
    assert src =~ "assertSameNode"
    # Identity, not equality: JSONObject.NULL.equals(null) is true, so an
    # equality-based null check silently accepted a real mismatch here once.
    assert src =~ "if (expected === null || actual === null)"
  end

  test "both Kotlin files land in a generated project, at the right paths" do
    # The generator's file list in mob.new.ex is only console output; templates
    # are actually picked up by a `**/*.eex` glob. So nothing in that list
    # guarantees these files ship — this does.
    tmp = Path.join(System.tmp_dir!(), "mobjson_gen_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(tmp) end)

    assert {:ok, _dir} = MobNew.ProjectGenerator.generate("genapp", tmp, no_ios: true)

    base = Path.join([tmp, "genapp", "android", "app", "src"])
    parser = Path.join([base, "main", "java", "com", "example", "genapp", "MobJson.kt"])
    tests = Path.join([base, "test", "java", "com", "example", "genapp", "MobJsonTest.kt"])

    assert File.exists?(parser), "MobJson.kt should be generated"
    assert File.exists?(tests), "MobJsonTest.kt should be generated"
    assert File.read!(parser) =~ "package com.example.genapp"
    refute File.read!(parser) =~ "<%="
  end

  test "the unit-test source set has a real org.json on its classpath" do
    # The Android SDK jar stubs org.json — every method throws — so without a
    # real implementation the parser's tests cannot run at all.
    src =
      File.read!(
        Path.expand("../../../priv/templates/mob.new/android/app/build.gradle.eex", __DIR__)
      )

    assert src =~ "testImplementation 'org.json:json"
    assert src =~ "testImplementation 'junit:junit"
  end
end
