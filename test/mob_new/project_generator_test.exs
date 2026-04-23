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

    test "generates MainActivity.kt in correct package path", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      kt = Path.join(dir, "android/app/src/main/java/com/mob/test_app/MainActivity.kt")
      assert File.exists?(kt)
    end

    test "MainActivity.kt has correct package declaration", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      kt = File.read!(Path.join(dir, "android/app/src/main/java/com/mob/test_app/MainActivity.kt"))
      assert kt =~ "package com.mob.test_app"
    end

    test "MainActivity.kt has correct loadLibrary name", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      kt = File.read!(Path.join(dir, "android/app/src/main/java/com/mob/test_app/MainActivity.kt"))
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

    test "beam_jni.c has correct BRIDGE_CLASS", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/jni/beam_jni.c"))
      assert content =~ ~s("com/mob/test_app/MobBridge")
    end

    test "generates MobBridge.kt in correct package path", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      path = Path.join(dir, "android/app/src/main/java/com/mob/test_app/MobBridge.kt")
      assert File.exists?(path)
    end

    test "MobBridge.kt has correct package declaration", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/java/com/mob/test_app/MobBridge.kt"))
      assert content =~ "package com.mob.test_app"
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

    test "CMakeLists.txt sqlite3_nif links to MOB_DEPS_DIR derived from relative path", %{tmp: tmp} do
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
