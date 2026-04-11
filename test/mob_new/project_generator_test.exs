defmodule MobNew.ProjectGeneratorTest do
  use ExUnit.Case, async: true

  alias MobNew.ProjectGenerator

  # ── assigns/1 ────────────────────────────────────────────────────────────────

  describe "assigns/1" do
    test "module_name is CamelCase of app_name" do
      assert ProjectGenerator.assigns("my_cool_app").module_name == "MyCoolApp"
    end

    test "single word app_name" do
      assert ProjectGenerator.assigns("myapp").module_name == "Myapp"
    end

    test "bundle_id uses com.mob prefix" do
      assert ProjectGenerator.assigns("my_app").bundle_id == "com.mob.my_app"
    end

    test "java_package matches bundle_id" do
      a = ProjectGenerator.assigns("cool_app")
      assert a.java_package == a.bundle_id
    end

    test "lib_name strips underscores" do
      assert ProjectGenerator.assigns("my_cool_app").lib_name == "mycoolapp"
    end

    test "lib_name with no underscores is unchanged" do
      assert ProjectGenerator.assigns("myapp").lib_name == "myapp"
    end

    test "java_path replaces dots with slashes" do
      assert ProjectGenerator.assigns("my_app").java_path == "com/mob/my_app"
    end

    test "display_name equals module_name" do
      a = ProjectGenerator.assigns("cool_app")
      assert a.display_name == a.module_name
    end

    test "app_name is preserved as-is" do
      assert ProjectGenerator.assigns("my_app").app_name == "my_app"
    end
  end

  # ── generate/2 ───────────────────────────────────────────────────────────────

  describe "generate/2" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "mob_new_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)
      {:ok, tmp: tmp}
    end

    test "returns {:ok, project_dir}", %{tmp: tmp} do
      assert {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert String.ends_with?(dir, "test_app")
    end

    test "creates project directory", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.dir?(dir)
    end

    test "returns error if directory already exists", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "test_app"))
      assert {:error, msg} = ProjectGenerator.generate("test_app", tmp)
      assert msg =~ "already exists"
    end

    test "generates mix.exs", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.exists?(Path.join(dir, "mix.exs"))
    end

    test "mix.exs contains correct app name", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "mix.exs"))
      assert content =~ "app: :test_app"
    end

    test "mix.exs contains correct module name", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "mix.exs"))
      assert content =~ "defmodule TestApp.MixProject"
    end

    test "generates app.ex", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.exists?(Path.join(dir, "lib/test_app/app.ex"))
    end

    test "app.ex references correct module and node name", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "lib/test_app/app.ex"))
      assert content =~ "TestApp.App"
      assert content =~ "test_app_android@127.0.0.1"
    end

    test "generates hello_screen.ex", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.exists?(Path.join(dir, "lib/test_app/hello_screen.ex"))
    end

    test "hello_screen.ex references correct module", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "lib/test_app/hello_screen.ex"))
      assert content =~ "TestApp.HelloScreen"
    end

    test "generates AndroidManifest.xml", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      manifest = Path.join(dir, "android/app/src/main/AndroidManifest.xml")
      assert File.exists?(manifest)
    end

    test "AndroidManifest.xml has correct bundle_id", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      manifest = File.read!(Path.join(dir, "android/app/src/main/AndroidManifest.xml"))
      assert manifest =~ ~s(package="com.mob.test_app")
    end

    test "generates MainActivity.java in correct package path", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      java = Path.join(dir, "android/app/src/main/java/com/mob/test_app/MainActivity.java")
      assert File.exists?(java)
    end

    test "MainActivity.java has correct package declaration", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      java = File.read!(Path.join(dir, "android/app/src/main/java/com/mob/test_app/MainActivity.java"))
      assert java =~ "package com.mob.test_app;"
    end

    test "MainActivity.java has correct loadLibrary name", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      java = File.read!(Path.join(dir, "android/app/src/main/java/com/mob/test_app/MainActivity.java"))
      assert java =~ ~s[System.loadLibrary("testapp")]
    end

    test "generates ios/beam_main.m", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.exists?(Path.join(dir, "ios/beam_main.m"))
    end

    test "beam_main.m has correct APP_MODULE", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "ios/beam_main.m"))
      assert content =~ ~s(#define APP_MODULE "test_app")
    end

    test "generates ios/Info.plist", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.exists?(Path.join(dir, "ios/Info.plist"))
    end

    test "Info.plist has correct bundle_id and display_name", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "ios/Info.plist"))
      assert content =~ "com.mob.test_app"
      assert content =~ "TestApp"
    end
  end
end
