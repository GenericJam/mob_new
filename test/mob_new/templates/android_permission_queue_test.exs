defmodule MobNew.Templates.AndroidPermissionQueueTest do
  # MobBridge.kt and MainActivity.kt call MobPermissionQueue (MOB-391). The
  # queue's behaviour is covered by the generated project's JVM unit tests
  # (MobPermissionQueueTest.kt, `./gradlew testDebugUnitTest`); this checks
  # that the class and its tests ship, so a generated app compiles.
  use ExUnit.Case, async: true

  alias MobNew.ProjectGenerator
  alias MobNew.Templates.Lint

  test "the queue and its unit tests land in a generated project with the app's package" do
    tmp = Path.join(System.tmp_dir!(), "permqueue_gen_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(tmp) end)

    assert {:ok, _dir} = ProjectGenerator.generate("genapp", tmp, no_ios: true)

    src = Path.join([tmp, "genapp", "android", "app", "src"])
    package_dir = Path.join(["java", "com", "example", "genapp"])

    for path <- [
          Path.join([src, "main", package_dir, "MobPermissionQueue.kt"]),
          Path.join([src, "test", package_dir, "MobPermissionQueueTest.kt"])
        ] do
      assert File.exists?(path), "#{path} should be generated"
      kotlin = File.read!(path)
      assert kotlin =~ "package com.example.genapp\n"
      assert Lint.no_eex_leaks(kotlin) == []
    end
  end
end
