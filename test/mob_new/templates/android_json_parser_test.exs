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
