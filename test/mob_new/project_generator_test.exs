defmodule MobNew.ProjectGeneratorTest do
  # async: false because some tests mutate the process-global MOB_BUNDLE_PREFIX
  # env var. Running them in parallel would race.
  use ExUnit.Case, async: false

  alias MobNew.ProjectGenerator

  # ── assigns/1 ────────────────────────────────────────────────────────────────

  describe "assigns/1" do
    test "module_name is CamelCase of app_name" do
      assert ProjectGenerator.assigns("my_cool_app").module_name == "MyCoolApp"
    end

    test "single word app_name" do
      assert ProjectGenerator.assigns("myapp").module_name == "Myapp"
    end

    test "bundle_id uses com.example prefix by default" do
      System.delete_env("MOB_BUNDLE_PREFIX")
      assert ProjectGenerator.assigns("my_app").bundle_id == "com.example.my_app"
    end

    test "bundle_id honors MOB_BUNDLE_PREFIX env var" do
      System.put_env("MOB_BUNDLE_PREFIX", "net.acme")

      try do
        assigns = ProjectGenerator.assigns("my_app")
        assert assigns.bundle_id == "net.acme.my_app"
        assert assigns.java_package == "net.acme.my_app"
        assert assigns.java_path == "net/acme/my_app"
      after
        System.delete_env("MOB_BUNDLE_PREFIX")
      end
    end

    test "empty MOB_BUNDLE_PREFIX falls back to com.example" do
      System.put_env("MOB_BUNDLE_PREFIX", "")

      try do
        assert ProjectGenerator.assigns("my_app").bundle_id == "com.example.my_app"
      after
        System.delete_env("MOB_BUNDLE_PREFIX")
      end
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
      assert ProjectGenerator.assigns("my_app").java_path == "com/example/my_app"
    end

    test "display_name equals module_name" do
      a = ProjectGenerator.assigns("cool_app")
      assert a.display_name == a.module_name
    end

    test "app_name is preserved as-is" do
      assert ProjectGenerator.assigns("my_app").app_name == "my_app"
    end
  end

  # ── liveview_phoenix_owned?/3 ────────────────────────────────────────────────
  #
  # Pure predicate: decides which native-template files must be skipped during
  # liveview_generate/3 so the freshly-generated Phoenix app's own files
  # (mix.exs with gettext/telemetry_metrics/etc., config/, lib/<app>/) survive
  # untouched. Regression target: any new template path that ends up
  # clobbering a Phoenix-owned file leaves the project unable to compile.

  describe "liveview_phoenix_owned?/3" do
    @root "/tmp/templates_root"

    defp owned?(rel, opts \\ [liveview: true]) do
      ProjectGenerator.liveview_phoenix_owned?(Path.join(@root, rel), @root, opts)
    end

    test "returns false when :liveview is not set (native path is unaffected)" do
      refute owned?("mix.exs.eex", [])
      refute owned?("config/config.exs.eex", [])
      refute owned?("lib/app_name/screen.ex.eex", [])
    end

    test "returns false when :liveview is explicitly false" do
      refute owned?("mix.exs.eex", liveview: false)
    end

    test "blocks mix.exs.eex (Phoenix's mix.exs has gettext/telemetry_metrics)" do
      assert owned?("mix.exs.eex")
    end

    test "blocks .gitignore.eex (Phoenix has its own)" do
      assert owned?(".gitignore.eex")
    end

    test "blocks .tool-versions.eex (Phoenix has its own)" do
      assert owned?(".tool-versions.eex")
    end

    test "blocks anything under config/" do
      assert owned?("config/config.exs.eex")
      assert owned?("config/dev.exs.eex")
      assert owned?("config/runtime.exs.eex")
    end

    test "blocks anything under lib/app_name/ (native screens collide with Phoenix lib)" do
      assert owned?("lib/app_name/screen.ex.eex")
      assert owned?("lib/app_name/audio.ex.eex")
      assert owned?("lib/app_name/webview.ex.eex")
    end

    test "blocks anything under priv/ (apply_liveview_patches owns repo migrations)" do
      assert owned?("priv/static/something.txt")
      assert owned?("priv/repo/migrations/foo.exs")
    end

    test "does NOT block native-only paths (android/, ios/, src/, mob.exs)" do
      refute owned?("android/app/src/main/AndroidManifest.xml.eex")
      refute owned?("android/build.gradle.eex")
      refute owned?("ios/beam_main.m")
      refute owned?("ios/Info.plist.eex")
      refute owned?("src/app_name.erl.eex")
      refute owned?("mob.exs.eex")
    end

    test "does NOT block lib/app_name_web (Mob doesn't ship a _web tree)" do
      # Defensive: even though there's no native template at this path today,
      # if one ever lands it should be skipped explicitly via the lib/app_name/
      # rule, not implicitly by sharing prefix. This test pins the negative case.
      refute owned?("lib/app_name_web/router.ex.eex")
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
      assert manifest =~ ~s(package="com.example.test_app")
    end

    test "generates MainActivity.kt in correct package path", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      kt = Path.join(dir, "android/app/src/main/java/com/example/test_app/MainActivity.kt")
      assert File.exists?(kt)
    end

    test "MainActivity.kt has correct package declaration", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)

      kt =
        File.read!(Path.join(dir, "android/app/src/main/java/com/example/test_app/MainActivity.kt"))

      assert kt =~ "package com.example.test_app"
    end

    test "MainActivity.kt has correct loadLibrary name", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)

      kt =
        File.read!(Path.join(dir, "android/app/src/main/java/com/example/test_app/MainActivity.kt"))

      assert kt =~ ~s[System.loadLibrary("testapp")]
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
      assert content =~ "com.example.test_app"
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
      assert content =~ "Java_com_example_test_1app_MainActivity_nativeSetActivity"
      assert content =~ "Java_com_example_test_1app_MainActivity_nativeStartBeam"
    end

    test "beam_jni.c has correct BRIDGE_CLASS", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/jni/beam_jni.c"))
      assert content =~ ~s("com/example/test_app/MobBridge")
    end

    test "generates MobBridge.kt in correct package path", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      path = Path.join(dir, "android/app/src/main/java/com/example/test_app/MobBridge.kt")
      assert File.exists?(path)
    end

    test "MobBridge.kt has correct package declaration", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)

      content =
        File.read!(Path.join(dir, "android/app/src/main/java/com/example/test_app/MobBridge.kt"))

      assert content =~ "package com.example.test_app"
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
      assert a.jni_package == "com_example_test_1app"
    end

    test "assigns jni_package with no underscores is unchanged" do
      a = ProjectGenerator.assigns("myapp")
      assert a.jni_package == "com_example_myapp"
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

    # ── State persistence ─────────────────────────────────────────────────────
    #
    # The home screen reads the persisted theme from Mob.State on mount so the
    # user's last selection is restored after an app kill. Theme changes are
    # written through to Mob.State so they survive the next restart.

    # ── Rock Paper Scissors (Ecto demo) ───────────────────────────────────────

    test "generates lib/app_name/round.ex schema", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.exists?(Path.join(dir, "lib/test_app/round.ex"))
    end

    test "round.ex uses correct module name and schema", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "lib/test_app/round.ex"))
      assert content =~ "defmodule TestApp.Round"
      assert content =~ ~s(schema "rounds")
      assert content =~ "user_choice"
      assert content =~ "computer_choice"
      assert content =~ "result"
    end

    test "generates rounds migration", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      migrations = Path.join(dir, "priv/repo/migrations")
      assert File.ls!(migrations) |> Enum.any?(&String.contains?(&1, "create_rounds"))
    end

    test "rounds migration creates the rounds table", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)

      migration =
        Path.join(dir, "priv/repo/migrations")
        |> File.ls!()
        |> Enum.find(&String.contains?(&1, "create_rounds"))

      content = File.read!(Path.join(dir, "priv/repo/migrations/#{migration}"))
      assert content =~ "TestApp.Repo.Migrations.CreateRounds"
      assert content =~ "create table(:rounds)"
    end

    test "app.ex runs migrations on start", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "lib/test_app/app.ex"))
      assert content =~ "Ecto.Migrator"
    end

    test "list_screen.ex is the RPS game screen", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "lib/test_app/list_screen.ex"))
      assert content =~ "Rock Paper Scissors"
      assert content =~ "TestApp.Round"
      assert content =~ "TestApp.Repo"
    end

    test "list_screen.ex has win/loss/draw outcome logic", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "lib/test_app/list_screen.ex"))
      assert content =~ ~s("win")
      assert content =~ ~s("loss")
      assert content =~ ~s("draw")
    end

    test "list_screen.ex uses Process.send_after for reveal delay", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "lib/test_app/list_screen.ex"))
      assert content =~ "Process.send_after"
      assert content =~ ":reveal"
    end

    test "home_screen.ex nav button label is Rock Paper Scissors", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "lib/test_app/home_screen.ex"))
      assert content =~ "Rock Paper Scissors"
      refute content =~ "Browse List"
    end

    test "text_screen.ex restores draft text from Mob.State on mount", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "lib/test_app/text_screen.ex"))
      assert content =~ "Mob.State.get(:draft_text"
      assert content =~ "Mob.State.put(:draft_text"
    end

    test "home_screen.ex restores theme from Mob.State on mount", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "lib/test_app/home_screen.ex"))
      assert content =~ "Mob.State.get(:theme"
    end

    test "home_screen.ex persists theme selection via Mob.State.put", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "lib/test_app/home_screen.ex"))
      assert content =~ "Mob.State.put(:theme"
    end

    # ── Ecto SQLite layer ─────────────────────────────────────────────────────
    #
    # Every generated app ships with Ecto + ecto_sqlite3 so developers get a
    # familiar Repo API without any extra setup. The native code (mob_beam.c /
    # mob_beam.m) sets MOB_DATA_DIR to the platform's persistent storage dir;
    # Repo.init/2 reads it to place the database file.

    test "mix.exs includes ecto_sqlite3 dependency", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "mix.exs"))
      assert content =~ "ecto_sqlite3"
    end

    test "generates lib/test_app/repo.ex", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.exists?(Path.join(dir, "lib/test_app/repo.ex"))
    end

    test "repo.ex uses correct module name and otp_app", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "lib/test_app/repo.ex"))
      assert content =~ "defmodule TestApp.Repo"
      assert content =~ "otp_app: :test_app"
      assert content =~ "Ecto.Adapters.SQLite3"
    end

    test "repo.ex init/2 reads MOB_DATA_DIR and sets pool_size: 1", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "lib/test_app/repo.ex"))
      assert content =~ "MOB_DATA_DIR"
      assert content =~ "pool_size: 1"
      assert content =~ "app.db"
    end

    test "app.ex starts ecto_sqlite3 apps and Repo in on_start", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "lib/test_app/app.ex"))
      assert content =~ "ensure_all_started(:ecto_sqlite3)"
      assert content =~ "TestApp.Repo.start_link()"
    end

    test "generates config/config.exs", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.exists?(Path.join(dir, "config/config.exs"))
    end

    test "config.exs registers ecto_repos", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "config/config.exs"))
      assert content =~ "ecto_repos: [TestApp.Repo]"
      assert content =~ ":test_app"
    end

    test "generates priv/repo/migrations/.keep", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.exists?(Path.join(dir, "priv/repo/migrations/.keep"))
    end

    test "CMakeLists.txt includes sqlite3_nif shared library target", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/jni/CMakeLists.txt"))
      assert content =~ "add_library(sqlite3_nif SHARED"
      assert content =~ "exqlite/c_src/sqlite3_nif.c"
      assert content =~ "exqlite/c_src/sqlite3.c"
    end

    test "CMakeLists.txt sqlite3_nif links to MOB_DEPS_DIR derived from relative path", %{
      tmp: tmp
    } do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/jni/CMakeLists.txt"))
      assert content =~ "MOB_DEPS_DIR"
      assert content =~ "CMAKE_CURRENT_SOURCE_DIR"
      # No hardcoded /Users/ paths
      refute content =~ "/Users/"
    end

    # ── CMake PRIVATE keyword — ERTS atom table isolation ────────────────────────
    #
    # target_link_libraries without the PRIVATE keyword defaults to PUBLIC in
    # CMake 3.x, propagating --whole-archive libbeam.a transitively to every
    # consumer of the main library — including sqlite3_nif. This gives
    # libsqlite3_nif.so its own uninitialized copy of the ERTS atom table
    # (duplicate T symbols), causing SIGSEGV on the first enif_make_atom call.
    # PRIVATE confines --whole-archive to the main app library only.

    test "CMakeLists.txt target_link_libraries uses PRIVATE to prevent --whole-archive propagation to sqlite3_nif",
         %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/jni/CMakeLists.txt"))
      assert content =~ "target_link_libraries(testapp\n    PRIVATE"
    end

    # ── MOB_BEAMS_DIR migration path — Ecto on flat -pa directories ──────────────
    #
    # Ecto.Migrator.run/3 uses :code.priv_dir(app) to find .exs files. That
    # function requires an OTP lib structure (lib/APP-VERSION/ebin/); Mob apps
    # deploy to a flat -pa dir so it returns {error, bad_name} and Ecto silently
    # logs "Migrations already up" without creating any tables. The fix is to
    # read MOB_BEAMS_DIR (set by mob_beam.c/mob_beam.m) and pass an explicit
    # path to Ecto.Migrator.run/4 instead.

    test "app.ex uses MOB_BEAMS_DIR env var to locate migrations on device", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "lib/test_app/app.ex"))
      assert content =~ "MOB_BEAMS_DIR"
      assert content =~ "migrations_dir()"
    end

    test "app.ex migrations_dir/0 passes explicit path to Ecto.Migrator.run", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "lib/test_app/app.ex"))
      # Uses run/4 with explicit path, not run/3 which calls :code.priv_dir internally
      assert content =~ "Ecto.Migrator.run(repo, migrations_dir()"
    end

    test "build.sh copies exqlite NIF to BEAMS_DIR priv", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "ios/build.sh"))
      assert content =~ "exqlite"
      assert content =~ "sqlite3_nif.so"
      assert content =~ "BEAMS_DIR/priv"
    end

    test "build.sh copies priv/repo migrations", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "ios/build.sh"))
      assert content =~ "priv/repo/migrations"
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

      content =
        File.read!(Path.join(dir, "android/app/src/main/java/com/example/test_app/MobBridge.kt"))

      assert content =~ "data class RootState(val navKey: Int,"
    end

    test "MobBridge.kt setRootJson increments navKey only on navigation transitions", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)

      content =
        File.read!(Path.join(dir, "android/app/src/main/java/com/example/test_app/MobBridge.kt"))

      assert content =~ "navKey + 1"
      assert content =~ ~s(transition != "none")
    end

    test "MainActivity.kt AnimatedContent uses contentKey on navKey", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)

      content =
        File.read!(Path.join(dir, "android/app/src/main/java/com/example/test_app/MainActivity.kt"))

      assert content =~ "contentKey"
      assert content =~ "it.navKey"
    end
  end

  # ── liveview_generate/3 ──────────────────────────────────────────────────────
  #
  # These tests call `mix phx.new` as a subprocess — tagged :integration so they
  # are excluded from the fast unit-test run. Run explicitly with:
  #
  #   mix test --only integration
  #
  # They require the phx_new archive to be installed:
  #   mix archive.install hex phx_new --force

  describe "liveview_generate/3" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "mob_new_lv_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)
      {:ok, tmp: tmp}
    end

    @tag :integration
    test "returns {:ok, project_dir}", %{tmp: tmp} do
      assert {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      assert String.ends_with?(dir, "lv_test")
    end

    @tag :integration
    test "creates project directory", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      assert File.dir?(dir)
    end

    @tag :integration
    test "returns error if directory already exists", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "lv_test"))
      assert {:error, msg} = ProjectGenerator.liveview_generate("lv_test", tmp)
      assert msg =~ "already exists"
    end

    @tag :integration
    test "generates mix.exs with mob dep", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      content = File.read!(Path.join(dir, "mix.exs"))
      assert content =~ ":mob"
      assert content =~ ":mob_dev"
    end

    @tag :integration
    test "mix.exs preserves Phoenix-owned deps (regression: native mix.exs.eex must not clobber Phoenix's)",
         %{tmp: tmp} do
      # The native template ships its own mix.exs.eex which has *only* :mob/:mob_dev.
      # If `liveview_phoenix_owned?/3` ever stops blocking it, the freshly-generated
      # Phoenix mix.exs gets overwritten and the project can no longer compile —
      # `Gettext` / `Telemetry.Metrics` come back as "module not loaded".
      # Pin every dep that phx.new --no-ecto puts in the file.
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      content = File.read!(Path.join(dir, "mix.exs"))

      assert content =~ ":phoenix,",
             "phx.new's mix.exs got clobbered — :phoenix dep is missing"

      assert content =~ ":phoenix_html",
             "phx.new's mix.exs got clobbered — :phoenix_html dep is missing"

      assert content =~ ":phoenix_live_view",
             "phx.new's mix.exs got clobbered — :phoenix_live_view dep is missing"

      assert content =~ ":gettext",
             "phx.new's mix.exs got clobbered — :gettext dep is missing"

      assert content =~ ":telemetry_metrics",
             "phx.new's mix.exs got clobbered — :telemetry_metrics dep is missing"

      assert content =~ ":telemetry_poller",
             "phx.new's mix.exs got clobbered — :telemetry_poller dep is missing"

      assert content =~ ":bandit",
             "phx.new's mix.exs got clobbered — :bandit dep is missing"

      assert content =~ ":jason",
             "phx.new's mix.exs got clobbered — :jason dep is missing"
    end

    @tag :integration
    test "config/config.exs is Phoenix's (regression: native config must not clobber Phoenix's)",
         %{tmp: tmp} do
      # Phoenix's config has Endpoint config, esbuild, tailwind, etc. The native
      # template's config has only logger + mob settings. If the blocklist
      # regresses on `config/`, none of the Phoenix wiring survives.
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      content = File.read!(Path.join(dir, "config/config.exs"))
      # Endpoint config is a marker only Phoenix's config has.
      assert content =~ "LvTestWeb.Endpoint",
             "phx.new's config/config.exs got clobbered — Endpoint config missing"
    end

    @tag :integration
    test ".gitignore is Phoenix's plus mob.exs patch", %{tmp: tmp} do
      # Phoenix's .gitignore ignores _build, deps, *.beam, etc. The native template
      # has its own slimmer version. The blocklist keeps Phoenix's; apply_liveview_patches
      # appends mob.exs to it. Both should be present — regression: clobbering Phoenix's
      # .gitignore would lose the standard Elixir/Phoenix exclusions.
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      content = File.read!(Path.join(dir, ".gitignore"))
      # _build is in every Phoenix-generated .gitignore, not in the bare-Mob one.
      assert content =~ "_build",
             "phx.new's .gitignore got clobbered — _build exclusion missing"
      # And the patch step still ran:
      assert content =~ "mob.exs"
    end

    @tag :integration
    test "generates mob_screen.ex", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      assert File.exists?(Path.join(dir, "lib/lv_test/mob_screen.ex"))
    end

    @tag :integration
    test "mob_screen.ex uses correct module name and Mob.Screen", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      content = File.read!(Path.join(dir, "lib/lv_test/mob_screen.ex"))
      assert content =~ "defmodule LvTest.MobScreen"
      assert content =~ "use Mob.Screen"
      assert content =~ "Mob.LiveView.local_url"
    end

    @tag :integration
    test "generates mob.exs with liveview_port", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      assert File.exists?(Path.join(dir, "mob.exs"))
      content = File.read!(Path.join(dir, "mob.exs"))
      assert content =~ "liveview_port: 4200"
    end

    @tag :integration
    test "mob.exs contains mob_dir and elixir_lib", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      content = File.read!(Path.join(dir, "mob.exs"))
      assert content =~ "mob_dir"
      assert content =~ "elixir_lib"
    end

    @tag :integration
    test "patches assets/js/app.js with MobHook", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      content = File.read!(Path.join(dir, "assets/js/app.js"))
      assert content =~ "const MobHook ="
      assert content =~ "hooks: {MobHook}"
      assert content =~ "pushEvent(\"mob_message\", data)"
    end

    @tag :integration
    test "patches root.html.heex with mob-bridge element", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)

      root_html =
        Path.join(dir, "lib/lv_test_web/components/layouts/root.html.heex")

      assert File.exists?(root_html)
      content = File.read!(root_html)
      assert content =~ ~s(id="mob-bridge")
      assert content =~ ~s(phx-hook="MobHook")
    end

    @tag :integration
    test "generates lib/<app>/mob_app.ex BEAM entry point", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      assert File.exists?(Path.join(dir, "lib/lv_test/mob_app.ex"))
    end

    @tag :integration
    test "mob_app.ex starts Phoenix app and MobScreen", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      content = File.read!(Path.join(dir, "lib/lv_test/mob_app.ex"))
      assert content =~ "defmodule LvTest.MobApp"
      assert content =~ "ensure_all_started(:lv_test)"
      assert content =~ "Mob.Screen.start_root(LvTest.MobScreen)"
    end

    @tag :integration
    test "generates src/<app>.erl Erlang bootstrap", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      assert File.exists?(Path.join(dir, "src/lv_test.erl"))
    end

    @tag :integration
    test "src/lv_test.erl calls MobApp not App", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      content = File.read!(Path.join(dir, "src/lv_test.erl"))
      assert content =~ "'Elixir.LvTest.MobApp':start()"
      refute content =~ "'Elixir.LvTest.App':start()"
    end

    @tag :integration
    test "mix.exs has erlc_paths: [\"src\"]", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      content = File.read!(Path.join(dir, "mix.exs"))
      assert content =~ ~s(erlc_paths: ["src"])
    end

    @tag :integration
    test "application.ex is NOT patched (Phoenix owns supervision tree)", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      content = File.read!(Path.join(dir, "lib/lv_test/application.ex"))
      # Mob.App should NOT be added to the Phoenix supervision tree
      refute content =~ "Mob.App"
    end

    @tag :integration
    test "generates Android boilerplate", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      assert File.exists?(Path.join(dir, "android/app/src/main/AndroidManifest.xml"))

      assert File.exists?(
               Path.join(dir, "android/app/src/main/java/com/example/lv_test/MainActivity.kt")
             )
    end

    @tag :integration
    test "generates iOS boilerplate", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      assert File.exists?(Path.join(dir, "ios/beam_main.m"))
      assert File.exists?(Path.join(dir, "ios/Info.plist"))
    end

    @tag :integration
    test ".gitignore excludes mob.exs", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      content = File.read!(Path.join(dir, ".gitignore"))
      assert content =~ "mob.exs"
    end

    @tag :integration
    test "generates android/gradlew as executable", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      {:ok, %{mode: mode}} = File.stat(Path.join(dir, "android/gradlew"))
      assert Bitwise.band(mode, 0o100) != 0
    end

    @tag :integration
    test "generates local dep paths when --local flag set", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp, local: true)
      content = File.read!(Path.join(dir, "mix.exs"))
      assert content =~ ~s(path:)
    end

    # ── Notes starter app ─────────────────────────────────────────────────────

    @tag :integration
    test "mix.exs includes ecto_sqlite3", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      assert File.read!(Path.join(dir, "mix.exs")) =~ "ecto_sqlite3"
    end

    @tag :integration
    test "generates lib/lv_test/repo.ex", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      content = File.read!(Path.join(dir, "lib/lv_test/repo.ex"))
      assert content =~ "defmodule LvTest.Repo"
      assert content =~ "Ecto.Adapters.SQLite3"
      assert content =~ "MOB_DATA_DIR"
    end

    @tag :integration
    test "generates lib/lv_test/note.ex schema", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      content = File.read!(Path.join(dir, "lib/lv_test/note.ex"))
      assert content =~ "defmodule LvTest.Note"
      assert content =~ ~s(schema "notes")
    end

    @tag :integration
    test "generates lib/lv_test/notes.ex context", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      content = File.read!(Path.join(dir, "lib/lv_test/notes.ex"))
      assert content =~ "defmodule LvTest.Notes"
      assert content =~ "def list"
      assert content =~ "def create"
    end

    @tag :integration
    test "generates create_notes migration", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      migration = Path.join(dir, "priv/repo/migrations/20260424000000_create_notes.exs")
      assert File.exists?(migration)
      assert File.read!(migration) =~ "create table(:notes)"
    end

    @tag :integration
    test "generates NotesListLive, NoteEditorLive, AboutLive", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      live = fn f -> Path.join(dir, "lib/lv_test_web/live/#{f}") end
      assert File.exists?(live.("notes_list_live.ex"))
      assert File.exists?(live.("note_editor_live.ex"))
      assert File.exists?(live.("about_live.ex"))
    end

    @tag :integration
    test "router has notes routes", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      content = File.read!(Path.join(dir, "lib/lv_test_web/router.ex"))
      assert content =~ ~s(live "/", NotesListLive)
      assert content =~ ~s(live "/notes/:id", NoteEditorLive)
      assert content =~ ~s(live "/about", AboutLive)
    end

    @tag :integration
    test "application.ex has Repo in supervision tree", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      content = File.read!(Path.join(dir, "lib/lv_test/application.ex"))
      assert content =~ "LvTest.Repo"
      refute content =~ "Mob.App"
    end

    @tag :integration
    test "config.exs has ecto_repos", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      content = File.read!(Path.join(dir, "config/config.exs"))
      assert content =~ "ecto_repos: [LvTest.Repo]"
    end

    @tag :integration
    test "dev.exs has Repo database config", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      content = File.read!(Path.join(dir, "config/dev.exs"))
      assert content =~ "LvTest.Repo"
      assert content =~ "database:"
    end

    @tag :integration
    test "mob_app.ex starts ecto_sqlite3 and runs migrations", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      content = File.read!(Path.join(dir, "lib/lv_test/mob_app.ex"))
      assert content =~ "ensure_all_started(:ecto_sqlite3)"
      assert content =~ "Ecto.Migrator"
      assert content =~ "MOB_BEAMS_DIR"
    end
  end

  describe "generate/3 with platform exclusion" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "mob_new_platform_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)
      {:ok, tmp: tmp}
    end

    test "default emits both android/ and ios/", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_both", tmp)
      assert File.dir?(Path.join(dir, "android"))
      assert File.dir?(Path.join(dir, "ios"))
    end

    test "no_ios: true skips ios/ but keeps android/", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_android", tmp, no_ios: true)
      assert File.dir?(Path.join(dir, "android"))
      refute File.dir?(Path.join(dir, "ios"))
    end

    test "no_android: true skips android/ but keeps ios/", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_ios", tmp, no_android: true)
      refute File.dir?(Path.join(dir, "android"))
      assert File.dir?(Path.join(dir, "ios"))
    end

    test "common files (mix.exs, lib/) emit regardless of platform exclusion", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_ios2", tmp, no_android: true)
      assert File.exists?(Path.join(dir, "mix.exs"))
      assert File.exists?(Path.join(dir, "lib/test_ios2/app.ex"))
      assert File.exists?(Path.join(dir, "lib/test_ios2/home_screen.ex"))
    end
  end
end
