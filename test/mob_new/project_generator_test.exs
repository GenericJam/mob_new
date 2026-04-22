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

    test "generates home_screen.ex", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.exists?(Path.join(dir, "lib/test_app/home_screen.ex"))
    end

    test "home_screen.ex references correct module", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "lib/test_app/home_screen.ex"))
      assert content =~ "TestApp.HomeScreen"
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

    test "generates android/local.properties", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.exists?(Path.join(dir, "android/local.properties"))
    end

    test "generates android JNI CMakeLists.txt", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.exists?(Path.join(dir, "android/app/src/main/jni/CMakeLists.txt"))
    end

    test "CMakeLists.txt uses lib_name for project and library", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/jni/CMakeLists.txt"))
      assert content =~ "project(testapp)"
      assert content =~ "add_library(testapp SHARED"
    end

    test "CMakeLists.txt uses CMake variables not hardcoded paths", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/jni/CMakeLists.txt"))
      assert content =~ "${OTP_RELEASE}"
      assert content =~ "${MOB_DIR}"
      refute content =~ "${OTP_BUILD}"
      refute content =~ "/Users/"
    end

    test "generates android JNI beam_jni.c", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.exists?(Path.join(dir, "android/app/src/main/jni/beam_jni.c"))
    end

    test "beam_jni.c has correct APP_MODULE and JNI method names", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/jni/beam_jni.c"))
      assert content =~ ~s(#define APP_MODULE    "test_app")
      assert content =~ "Java_com_mob_test_1app_MainActivity_nativeSetActivity"
      assert content =~ "Java_com_mob_test_1app_MainActivity_nativeStartBeam"
    end

    test "beam_jni.c has correct BRIDGE_CLASS and TAP_CLASS", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/jni/beam_jni.c"))
      assert content =~ ~s("com/mob/test_app/MobBridge")
      assert content =~ ~s("com/mob/test_app/MobTapListener")
    end

    test "generates MobBridge.java in correct package path", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      path = Path.join(dir, "android/app/src/main/java/com/mob/test_app/MobBridge.java")
      assert File.exists?(path)
    end

    test "MobBridge.java has correct package declaration", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/java/com/mob/test_app/MobBridge.java"))
      assert content =~ "package com.mob.test_app;"
    end

    test "generates MobTapListener.java in correct package path", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      path = Path.join(dir, "android/app/src/main/java/com/mob/test_app/MobTapListener.java")
      assert File.exists?(path)
    end

    test "app/build.gradle reads local.properties for CMake paths", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/build.gradle"))
      assert content =~ "local.properties"
      assert content =~ "mob.otp_release"
      refute content =~ "mob.otp_build"
      refute content =~ "MOB_OTP_SRC"
    end

    test "assigns jni_package escapes underscores correctly" do
      a = ProjectGenerator.assigns("test_app")
      assert a.jni_package == "com_mob_test_1app"
    end

    test "assigns jni_package with no underscores is unchanged" do
      a = ProjectGenerator.assigns("myapp")
      assert a.jni_package == "com_mob_myapp"
    end

    test "generates ios/AppDelegate.m", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.exists?(Path.join(dir, "ios/AppDelegate.m"))
    end

    test "AppDelegate.m imports MobApp-Swift.h (standardized header name)", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "ios/AppDelegate.m"))
      assert content =~ ~s(#import "MobApp-Swift.h")
    end

    test "generates ios/build.sh", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.exists?(Path.join(dir, "ios/build.sh"))
    end

    test "build.sh is executable", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      {:ok, %{mode: mode}} = File.stat(Path.join(dir, "ios/build.sh"))
      assert Bitwise.band(mode, 0o100) != 0
    end

    test "build.sh references correct app name", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "ios/build.sh"))
      assert content =~ "test_app/ebin"
    end

    test "build.sh uses env vars for paths", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "ios/build.sh"))
      assert content =~ "MOB_DIR"
      assert content =~ "MOB_ELIXIR_LIB"
      assert content =~ "MOB_IOS_OTP_ROOT"
      refute content =~ "MOB_OTP_SRC"
    end

    test "generates mob.exs config template", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.exists?(Path.join(dir, "mob.exs"))
    end

    test "mob.exs mentions mob_dir and elixir_lib but not otp_src", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "mob.exs"))
      assert content =~ "mob_dir"
      assert content =~ "elixir_lib"
      refute content =~ "otp_src"
    end

    test "generates .gitignore", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.exists?(Path.join(dir, ".gitignore"))
    end

    test ".gitignore excludes mob.exs", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, ".gitignore"))
      assert content =~ "mob.exs"
    end

    test "generates android/gradlew", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.exists?(Path.join(dir, "android/gradlew"))
    end

    test "android/gradlew is executable", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      {:ok, %{mode: mode}} = File.stat(Path.join(dir, "android/gradlew"))
      assert Bitwise.band(mode, 0o100) != 0
    end

    test "generates android/gradle/wrapper/gradle-wrapper.jar", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      jar = Path.join(dir, "android/gradle/wrapper/gradle-wrapper.jar")
      assert File.exists?(jar)
      assert File.stat!(jar).size > 0
    end

    test "generates android/gradle/wrapper/gradle-wrapper.properties", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      props = Path.join(dir, "android/gradle/wrapper/gradle-wrapper.properties")
      assert File.exists?(props)
      assert File.read!(props) =~ "distributionUrl"
    end

    # ── Erlang bootstrap ───────────────────────────────────────────────────────

    test "generates src/test_app.erl bootstrap", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.exists?(Path.join(dir, "src/test_app.erl"))
    end

    test "src/test_app.erl has correct module, export, and Elixir App call", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "src/test_app.erl"))
      assert content =~ "-module(test_app)."
      assert content =~ "-export([start/0])."
      assert content =~ "'Elixir.TestApp.App':start()"
    end

    test "mix.exs has erlc_paths: [\"src\"]", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "mix.exs"))
      assert content =~ ~s(erlc_paths: ["src"])
    end

    test "mix.exs does not include avatarex or image deps", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "mix.exs"))
      refute content =~ "avatarex"
      refute content =~ ~s({:image,)
    end

    # ── Android icon ───────────────────────────────────────────────────────────

    test "AndroidManifest.xml has android:icon attribute", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/AndroidManifest.xml"))
      assert content =~ ~s(android:icon="@mipmap/ic_launcher")
    end

    # ── iOS icon ───────────────────────────────────────────────────────────────

    test "Info.plist has CFBundleIconName set to AppIcon", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "ios/Info.plist"))
      assert content =~ "CFBundleIconName"
      assert content =~ "AppIcon"
    end

    test "build.sh does not use xcrun simctl launch --console", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "ios/build.sh"))
      refute content =~ "--console"
    end

    test "build.sh merges actool partial plist into Info.plist", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "ios/build.sh"))
      assert content =~ "PlistBuddy"
      assert content =~ "Merge"
      assert content =~ "output-partial-info-plist"
    end

    test "build.sh BEAMS_DIR uses app_name not a hardcoded value", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "ios/build.sh"))
      assert content =~ ~s(BEAMS_DIR="$OTP_ROOT/test_app")
      refute content =~ "beamhello"
    end

    test "build.sh spot-check references Elixir module beam not app_name.beam", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "ios/build.sh"))
      assert content =~ "Elixir.TestApp.App.beam"
    end

    # ── Keyboard dismissal fix ─────────────────────────────────────────────────
    #
    # AnimatedContent used to key on the entire RootState (node + transition),
    # which meant every BEAM re-render (transition == "none") swapped composable
    # content, dropped focus, and dismissed the keyboard. The fix is:
    #   1. RootState carries a navKey integer that only increments on actual
    #      navigation transitions (push/pop/reset).
    #   2. AnimatedContent uses contentKey = { it.navKey } so same-screen renders
    #      recompose in place — no content swap, no focus loss, no keyboard dismissal.

    test "MobBridge.kt RootState has navKey as first field", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/java/com/mob/test_app/MobBridge.kt"))
      assert content =~ "data class RootState(val navKey: Int,"
    end

    test "MobBridge.kt setRootJson increments navKey only on navigation transitions", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/java/com/mob/test_app/MobBridge.kt"))
      assert content =~ "navKey + 1"
      assert content =~ ~s(transition != "none")
    end

    test "MainActivity.kt AnimatedContent uses contentKey on navKey", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/java/com/mob/test_app/MainActivity.kt"))
      assert content =~ "contentKey"
      assert content =~ "it.navKey"
    end
  end
end
