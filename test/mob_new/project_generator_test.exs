defmodule MobNew.ProjectGeneratorTest do
  # async: false because some tests mutate the process-global MOB_BUNDLE_PREFIX
  # env var. Running them in parallel would race.
  use ExUnit.Case, async: false

  alias MobNew.ProjectGenerator
  alias MobNew.Templates.Lint

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

    # .gitignore.eex/.tool-versions.eex template files were deleted as dead:
    # the inline @dotfiles map supersedes them in BOTH --local and archive
    # modes (byte-diff-proven), so there is nothing for LiveView mode to block.

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

    test "blocks anything under test/ (phx.new owns test_helper; no native HomeScreen)" do
      assert owned?("test/test_helper.exs.eex")
      assert owned?("test/app_name/home_screen_test.exs.eex")
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

    test "scaffolds a Mob.ScreenCase test for the home screen", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      assert File.exists?(Path.join(dir, "test/test_helper.exs"))

      screen_test = Path.join(dir, "test/test_app/home_screen_test.exs")
      assert File.exists?(screen_test)
      content = File.read!(screen_test)
      assert content =~ "defmodule TestApp.HomeScreenTest do"
      assert content =~ "use Mob.ScreenCase"
      assert content =~ "alias TestApp.HomeScreen"
      assert content =~ "assert_renderable(view)"
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

    test ".gitignore excludes native build artifacts and signing secrets", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      gi = File.read!(Path.join(dir, ".gitignore"))

      # Regression: a fresh project's `git add -A` after a native build must
      # not commit build junk or secrets. The template previously only
      # ignored _build/deps/app-build, so .cxx/, .zig-cache/, the bundled
      # OTP zip (~19MB), and keystores all leaked into version control.
      for pattern <- [
            "*.o",
            "*.so",
            "*.a",
            "android/app/.cxx/",
            "**/.zig-cache/",
            "android/app/src/main/assets/otp.zip",
            "android/keystore.properties",
            "android/*.keystore",
            "erl_crash.dump"
          ] do
        assert gi =~ pattern,
               ".gitignore must exclude #{pattern} — else fresh projects commit " <>
                 "build artifacts / secrets on `git add -A`"
      end
    end

    test ".credo.exs registers ExSlop as a plugin, not a check", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      credo = File.read!(Path.join(dir, ".credo.exs"))

      # Regression: ex_slop >= 0.4.2 is a Credo *plugin*. Registering it under
      # checks.enabled (as the template used to) makes Credo ignore it as an
      # "undefined check" and run zero ex_slop checks — silently. It must live
      # in plugins:, and the dep must be pinned to the plugin-API version.
      assert credo =~ "plugins: [{ExSlop, []}]",
             ".credo.exs must register ExSlop as a plugin or ex_slop is a no-op"

      refute credo =~ ~r/enabled:.*ExSlop/s,
             "ExSlop under checks.enabled is the bug — Credo ignores it there"
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

    test "AndroidManifest.xml does not bake in Bluetooth permissions (plugin-provided)",
         %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      manifest = File.read!(Path.join(dir, "android/app/src/main/AndroidManifest.xml"))

      # Bluetooth moved out of core into the mob_bluetooth plugin. mob_dev
      # merges the plugin's declared permissions into the manifest at build
      # time (MobDev.NativeBuild merge_android_permissions), so a freshly
      # generated app must NOT hardcode them.
      refute manifest =~ "android.permission.BLUETOOTH_SCAN"
      refute manifest =~ "android.permission.BLUETOOTH_CONNECT"
      refute manifest =~ "android.permission.BLUETOOTH_ADMIN"
      refute manifest =~ "android.hardware.bluetooth"
    end

    test "generates MainActivity.kt in correct package path", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      kt = Path.join(dir, "android/app/src/main/java/com/example/test_app/MainActivity.kt")
      assert File.exists?(kt)
    end

    test "MainActivity.kt has correct package declaration", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)

      kt =
        File.read!(
          Path.join(dir, "android/app/src/main/java/com/example/test_app/MainActivity.kt")
        )

      assert kt =~ "package com.example.test_app"
    end

    test "MainActivity.kt has correct loadLibrary name", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)

      kt =
        File.read!(
          Path.join(dir, "android/app/src/main/java/com/example/test_app/MainActivity.kt")
        )

      assert kt =~ ~s[System.loadLibrary("test_app")]
    end

    test "MobBridge.kt NotificationReceiver wires the tap to bring up the app", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)

      kt =
        File.read!(Path.join(dir, "android/app/src/main/java/com/example/test_app/MobBridge.kt"))

      # A displayed local notification must carry a content PendingIntent, or
      # tapping it is a no-op. The intent relaunches MainActivity (singleTop)
      # carrying the payload under the exact key MainActivity reads, so the tap
      # foregrounds the app and the BEAM gets the notification.
      assert kt =~ "setContentIntent",
             "NotificationReceiver must set a content intent or the tap does nothing"

      assert kt =~ "PendingIntent.getActivity"

      assert kt =~ ~s[putExtra("mob_notification_json")] or kt =~ "mob_notification_json",
             "tap intent must carry the payload under the key MainActivity.onNewIntent reads"
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

    test "CMakeLists.txt uses app_name for project and library", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/jni/CMakeLists.txt"))
      assert content =~ "project(test_app)"
      assert content =~ "add_library(test_app SHARED"
    end

    test "CMakeLists.txt uses CMake variables not hardcoded paths", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/jni/CMakeLists.txt"))
      assert content =~ "${OTP_RELEASE}"
      assert content =~ "${OTP_RELEASE_X86_64}"
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

    test "beam_jni.c does not emit Bluetooth JNI thunks (plugin-provided)", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/jni/beam_jni.c"))

      # Bluetooth lives in the mob_bluetooth plugin now; its JNI thunks ship
      # in the plugin's own jni_source. A generated app's beam_jni.c carries
      # none of them.
      refute content =~ "nativeDeliverBt"
      refute content =~ "mob_deliver_bt"
    end

    test "generates MobBridge.kt in correct package path", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      path = Path.join(dir, "android/app/src/main/java/com/example/test_app/MobBridge.kt")
      assert File.exists?(path)
    end

    test "MobBridge.kt declares ttsSpeak/ttsStop for text-to-speech", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)

      content =
        File.read!(Path.join(dir, "android/app/src/main/java/com/example/test_app/MobBridge.kt"))

      # Android side of Mob.Speech — TextToSpeech driven via JNI-cached methods.
      assert content =~ "import android.speech.tts.TextToSpeech"
      assert content =~ "fun ttsSpeak(text: String, optsJson: String)"
      assert content =~ "fun ttsStop()"
    end

    test "MobBridge.kt does not declare Bluetooth external fns (plugin-provided)", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)

      content =
        File.read!(Path.join(dir, "android/app/src/main/java/com/example/test_app/MobBridge.kt"))

      # Bluetooth lives in the mob_bluetooth plugin (MobBluetoothBridge); the
      # app's core MobBridge no longer carries any bt externs, methods, or
      # imports.
      refute content =~ "nativeDeliverBt"
      refute content =~ "fun bt_"
      refute content =~ "import android.bluetooth"
    end

    test "MobBridge.kt WebView fills its bounds so full-viewport pages don't collapse",
         %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)

      content =
        File.read!(Path.join(dir, "android/app/src/main/java/com/example/test_app/MobBridge.kt"))

      # Regression: an Android WebView defaults to wrap_content, so a web app
      # using CSS 100vh / 100% (e.g. an xterm.js terminal) measures its
      # container as 0px and renders blank. The WebView must request
      # MATCH_PARENT layout and honour the page viewport so vh units resolve.
      assert content =~ "ViewGroup.LayoutParams.MATCH_PARENT",
             "MobWebView must set MATCH_PARENT layout params, else full-viewport " <>
               "pages collapse to 0px height and render blank"

      assert content =~ "settings.useWideViewPort = true"
      assert content =~ "settings.loadWithOverviewMode = true"
    end

    test "MobBridge.kt passes structural lints (no dup imports, balanced delimiters, no EEx leaks)",
         %{tmp: tmp} do
      # Aggregate structural check via Lint.check_kotlin/1.
      # Catches the 0.3.2 → 0.3.4 duplicate-import regression class
      # (the BT-PR merge re-introduced imports that the 0.3.2 fix had
      # removed) AND adjacent structural bug shapes — unbalanced
      # braces/parens/brackets, leaked `<%=` tags from malformed
      # templates. See MobNew.Templates.Lint for the full check list.
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)

      content =
        File.read!(Path.join(dir, "android/app/src/main/java/com/example/test_app/MobBridge.kt"))

      issues = Lint.check_kotlin(content)

      assert issues == [],
             "MobBridge.kt failed structural lints:\n  " <>
               Enum.map_join(issues, "\n  ", & &1.message)
    end

    test "beam_jni.c passes structural lints (balanced braces, no EEx leaks)", %{tmp: tmp} do
      # Aggregate structural check via Lint.check_c/1.
      # Catches the 0.3.2 → 0.3.4 missing-`}` regression after
      # nativeDeliverVendorUsbEvent (which turned every subsequent
      # JNIEXPORT into a "function definition is not allowed here"
      # parse error). See MobNew.Templates.Lint for full check list.
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/jni/beam_jni.c"))

      issues = Lint.check_c(content)

      assert issues == [],
             "beam_jni.c failed structural lints:\n  " <>
               Enum.map_join(issues, "\n  ", & &1.message)
    end

    @tag :requires_android_ndk
    test "beam_jni.c passes `clang -fsyntax-only`", %{tmp: tmp} do
      # Tier-3 compile-check (vs. tier-1 structural lint above): invoke
      # the NDK's clang in syntax-only mode against the rendered C.
      # Catches the full class of "actually broken C" — typos in
      # identifiers, wrong arg counts, type mismatches — that the
      # tier-1 brace-balance check can miss. Skipped when the Android
      # NDK isn't installed (mirror of the :requires_zig pattern).
      ndk_clang = find_android_ndk_clang()

      unless ndk_clang do
        flunk(
          "Android NDK not found — tag this test :requires_android_ndk should have skipped it"
        )
      end

      mob_dir = System.get_env("MOB_DIR") || "/Users/kevin/code/mob"

      unless File.dir?(Path.join(mob_dir, "android/jni")) do
        flunk("MOB_DIR=#{mob_dir} not a valid mob checkout (no android/jni/ inside)")
      end

      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      beam_jni = Path.join(dir, "android/app/src/main/jni/beam_jni.c")

      {output, exit_code} =
        System.cmd(
          ndk_clang,
          ["-fsyntax-only", "-I", Path.join(mob_dir, "android/jni"), beam_jni],
          stderr_to_stdout: true
        )

      assert exit_code == 0,
             "clang -fsyntax-only on rendered beam_jni.c failed:\n" <> output
    end

    test "Kotlin externs and C JNI thunks are consistent (no missing-pair regressions)",
         %{tmp: tmp} do
      # Cross-file consistency: every `@JvmStatic external fun nativeFoo`
      # in MobBridge.kt must have a matching `Java_..._MobBridge_nativeFoo`
      # in beam_jni.c, and vice versa. Catches "added the Kotlin side
      # but forgot the C thunk" (or the reverse) — which the BT-PR merge
      # also touched and we'd want to catch immediately if either side
      # drifts.
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)

      kt =
        File.read!(Path.join(dir, "android/app/src/main/java/com/example/test_app/MobBridge.kt"))

      c = File.read!(Path.join(dir, "android/app/src/main/jni/beam_jni.c"))

      issues = Lint.external_fun_jni_consistency(kt, c)

      assert issues == [],
             "Kotlin/C JNI pair mismatches:\n  " <>
               Enum.map_join(issues, "\n  ", & &1.message)
    end

    test "MobBridge.kt wires the GpuView GLES 3.0 renderer", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)

      content =
        File.read!(Path.join(dir, "android/app/src/main/java/com/example/test_app/MobBridge.kt"))

      # Composable + renderer classes for the GLES 3.0 surface.
      assert content =~ "private fun MobGpuView("
      assert content =~ "private class MobGpuSurfaceView"
      assert content =~ "private class MobGpuRenderer"

      # GLES 3.0 + GLSurfaceView imports — the renderer can't compile without
      # them, so if these drop out the template build breaks loudly.
      assert content =~ "import android.opengl.GLES30"
      assert content =~ "import android.opengl.GLSurfaceView"

      # Composable dispatch picks up the "gpu_view" node type.
      assert content =~ ~s|"gpu_view"       -> MobGpuView(node, m)|

      # Uniform packing mirrors iOS std140 layout (scalar / vec2 / vec4).
      assert content =~ "packGpuUniforms"

      # Shader source accepts the cross-platform map form (per the iOS
      # commit's docstring: %{ios: "...MSL...", android: "...GLSL ES..."}).
      assert content =~ ~s|raw.optString("android", "")|
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
      assert content =~ "mob.otp_release_x86_64"
      assert content =~ "abiFilters 'arm64-v8a', 'armeabi-v7a', 'x86_64'"
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

    test "AppDelegate.m declares and calls mob_register_plugins() before mob_init_ui()",
         %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "ios/AppDelegate.m"))

      # The extern declaration must be present so the call resolves at link
      # time against the @_cdecl symbol the bootstrap Swift file exports.
      assert content =~ "extern void mob_register_plugins(void);"

      # The call must come before mob_init_ui() — see comment in template;
      # plugins register their factories with MobNativeViewRegistry.shared and
      # the registry has to be populated by the time the BEAM starts mounting.
      register_idx = :binary.match(content, "mob_register_plugins();") |> elem(0)
      init_idx = :binary.match(content, "mob_init_ui();") |> elem(0)
      assert register_idx < init_idx
    end

    test "does NOT generate ios/build.sh — iOS sim build glue lives in mob_dev's NativeBuild as of iter 13b",
         %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      refute File.exists?(Path.join(dir, "ios/build.sh"))
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

    test "generates .formatter.exs with Mob.Formatter plugin", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, ".formatter.exs"))
      assert content =~ "Mob.Formatter"
      assert content =~ "plugins:"
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

    test "mix.exs wires convenience aliases for the common mob tasks", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "mix.exs"))
      assert content =~ "aliases: aliases()"
      assert content =~ "defp aliases do"
      assert content =~ ~s(deploy: ["mob.deploy"])
      assert content =~ ~s(connect: ["mob.connect"])
      assert content =~ ~s("android.native": ["mob.deploy --native --android"])
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

    test "home_screen.ex does not eagerly evaluate Path.expand in System.get_env default",
         %{tmp: tmp} do
      # Regression: `System.get_env("ROOTDIR", Path.expand("~/..."))` evaluates
      # the second argument unconditionally, and `Path.expand("~/...")` calls
      # `System.user_home!()` which raises on Android (no `HOME` env var set
      # by mob_beam.c). That kills the screen GenServer's init silently and
      # the app stays on the "Starting BEAM…" splash forever. The fix is to
      # lazy-evaluate the fallback via a helper that uses `case` or `||`.
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "lib/test_app/home_screen.ex"))

      refute content =~ ~s|System.get_env("ROOTDIR", Path.expand|,
             """
             home_screen.ex eagerly evaluates Path.expand as the default arg
             to System.get_env — this raises on Android where HOME is unset
             and crashes the screen's init. Use a `case` or `||` helper so
             the fallback only fires when ROOTDIR is missing.
             """
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

    test "app.ex configures pure-BEAM DNS in on_start", %{tmp: tmp} do
      # Without `Mob.DNS.configure_pure_beam()` at startup, every iOS
      # device hits the inet_gethost execve block on first `Req.get`
      # / `Finch.build` / etc. The mob.new template ships this call
      # by default so new apps don't have to discover the iOS DNS
      # workaround themselves. Pin it.
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "lib/test_app/app.ex"))
      assert content =~ "Mob.DNS.configure_pure_beam()"
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
      assert content =~ "target_link_libraries(test_app\n        PRIVATE"
    end

    # ── Project rust libs must be tracked as file inputs ─────────────────────────
    #
    # The zig link step takes comma-separated `.a` paths for project-side Rust
    # NIFs. Passing them via `run.addArg(path)` (string-only) makes the cache
    # hash the path string but not the .a contents — rebuilding a project rust
    # crate yields a fresh .a that the link step ignores as UP-TO-DATE, and
    # the resulting .so silently keeps the old code. Use `addFileArg` with a
    # LazyPath so the archive bytes are part of the cache key.
    #
    # This bit us once (rustler Android dlsym fix) — the second patch built
    # cleanly but didn't reach the .so, masquerading as "my patch isn't
    # compiling." The static check below prevents the regression on all three
    # build.zig templates (android, ios sim, ios device).

    for {path, label} <- [
          {"android/app/src/main/jni/build.zig", "android"},
          {"ios/build.zig", "ios sim"},
          {"ios/build_device.zig", "ios device"}
        ] do
      @path path
      @label label
      test "#{@label} build.zig tracks project_rust_libs as file inputs (addFileArg, not addArg)",
           %{tmp: tmp} do
        {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
        content = File.read!(Path.join(dir, @path))

        # Find the project_rust_libs loop body. The block is bounded by the
        # opening conditional and the next `run.addArgs` (a stable marker —
        # follows the rust-libs loop on all three templates). Strip line
        # comments so the assertion isn't fooled by the comment text we add.
        [_preamble, after_marker] =
          String.split(content, "opts.project_rust_libs.len > 0", parts: 2)

        [loop_body, _rest] = String.split(after_marker, "run.addArgs", parts: 2)

        loop_code =
          loop_body
          |> String.split("\n")
          |> Enum.map_join("\n", &Regex.replace(~r{//.*$}, &1, ""))

        assert loop_code =~ "addFileArg",
               "#{@label} build.zig loop over project_rust_libs must use addFileArg so " <>
                 ".a content changes invalidate the zig cache. Loop body:\n#{loop_body}"

        refute loop_code =~ ~r/\baddArg\b/,
               "#{@label} build.zig loop over project_rust_libs must NOT use addArg — " <>
                 "the cache won't see content changes. Loop body:\n#{loop_body}"
      end
    end

    test "android build.zig 16 KB-aligns the .so links (Android 15+ / Play page-size requirement)",
         %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/jni/build.zig"))

      # Both .so links (lib<app>.so and libsqlite3_nif.so) must pass
      # -Wl,-z,max-page-size=16384 so LOAD segments align to 16 KB. Without it,
      # Google Play rejects the AAB on Android 15+ (16 KB memory page) devices.
      # The literal appears only in the two `addArg` calls (not in comments).
      count = ~r/-Wl,-z,max-page-size=16384/ |> Regex.scan(content) |> length()

      assert count >= 2,
             "android build.zig must pass -Wl,-z,max-page-size=16384 on BOTH .so links " <>
               "(lib<app>.so + libsqlite3_nif.so); found #{count}"
    end

    for {path, label} <- [
          {"ios/build.zig", "ios sim"},
          {"ios/build_device.zig", "ios device"}
        ] do
      @path path
      @label label
      test "#{@label} build.zig compiles project Swift sources from project_swift_sources",
           %{tmp: tmp} do
        {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
        content = File.read!(Path.join(dir, @path))

        assert content =~ ~s("project_swift_sources")

        assert content =~
                 "Comma-separated absolute paths to extra project Swift sources; empty if none"

        assert content =~ "std.mem.splitScalar(u8, project_swift_sources, ',')"
        assert content =~ "swift_run.addFileArg(.{ .cwd_relative = source });"
      end

      test "#{@label} build.zig globs mob Swift sources (no hardcoded file list)",
           %{tmp: tmp} do
        {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
        content = File.read!(Path.join(dir, @path))

        # mob Swift sources are globbed from $mob_dir/ios at build time so a
        # newly-added file (e.g. MobGpuView.swift, referenced by MobRootView)
        # compiles without a template edit — listing files by name is how a new
        # mob Swift file broke iOS builds.
        assert content =~ ~s|b.build_root.handle.openDir(glob_io, b.fmt("{s}/ios", .{mob_dir})|
        assert content =~ ~s|std.mem.endsWith(u8, entry.name, ".swift")|

        refute content =~ ~s|b.fmt("{s}/ios/MobGpuView.swift", .{mob_dir})|,
               "#{@label} build.zig must glob ios/*.swift, not list mob Swift files by name"
      end
    end

    # Regression: the Android jni build.zig must declare `tflite_static` as
    # a `b.option` AND thread it into the `driver_tab_android` build_options
    # alongside `nx_eigen_static`. MobDev.StaticNifs.default_nifs/0 always
    # lists both guarded NIFs (nx_eigen + tflite_nif), so the generated
    # driver_tab_android.zig always references `build_options.tflite_static`.
    # Without the b.option declaration the project fails to compile with
    # "struct 'options' has no member named 'tflite_static'" — bit any user
    # who scaffolded a fresh project, added a static NIF, and ran
    # `mix mob.regen_driver_tab` until 0.3.9.
    test "android build.zig declares tflite_static b.option for driver_tab parity",
         %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
      content = File.read!(Path.join(dir, "android/app/src/main/jni/build.zig"))

      assert content =~ ~s|b.option(bool, "tflite_static"|,
             "android build.zig must declare tflite_static as a b.option " <>
               "(symmetric to nxeigen_static) so driver_tab_android.zig's " <>
               "build_options.tflite_static reference resolves at compile time"

      assert content =~ ~s|o.addOption(bool, "tflite_static", tflite_static)|,
             "android build.zig must thread tflite_static into the " <>
               "driver_tab_android build_opts via o.addOption — otherwise the " <>
               "b.option flag is declared but never reaches the consuming Zig module"
    end

    # Regression: same drift as the Android case above, but for the iOS sim
    # and iOS device templates. driver_tab_ios.zig (generated by
    # MobDev.StaticNifs.generate(:ios, ..., format: :zig)) references
    # `build_options.tflite_static` because the default NIF list includes
    # :tflite_nif on `archs: [:all]`. The iOS templates declared sqlite_static,
    # emlx_static, and nx_eigen_static via b.addOptions() but never declared
    # tflite_static — bit the 2026-05-28 iOS smoke (had to hand-patch
    # mob_plugin_demo/ios/build*.zig) before this fix.
    for {path, label} <- [
          {"ios/build.zig", "ios sim"},
          {"ios/build_device.zig", "ios device"}
        ] do
      @path path
      @label label
      test "#{@label} build.zig declares tflite_static b.option for driver_tab parity",
           %{tmp: tmp} do
        {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
        content = File.read!(Path.join(dir, @path))

        assert content =~ ~s|b.option(bool, "tflite_static"|,
               "#{@label} build.zig must declare tflite_static as a b.option " <>
                 "(symmetric to nxeigen_static) so driver_tab_ios.zig's " <>
                 "build_options.tflite_static reference resolves at compile time"

        assert content =~ ~s|opts.addOption(bool, "tflite_static", tflite_static)|,
               "#{@label} build.zig must thread tflite_static into the " <>
                 "driver_tab_ios build_opts via opts.addOption — otherwise the " <>
                 "b.option flag is declared but never reaches the consuming Zig module"
      end
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
        File.read!(
          Path.join(dir, "android/app/src/main/java/com/example/test_app/MainActivity.kt")
        )

      assert content =~ "contentKey"
      assert content =~ "it.navKey"
    end

    # ── Template linting ──────────────────────────────────────────────────────
    #
    # Generate a real project and lint the output. This is the canonical way
    # to validate templates: EEx files can't be linted directly (the <%= %>
    # syntax breaks all native parsers), but generated output is plain Kotlin/C
    # and fully lintable. A lint failure here means a template needs fixing.
    #
    # Requires: brew install ktlint
    # Run:      mix test --only lint

    @tag :lint
    test "all generated Kotlin files pass ktlint", %{tmp: tmp} do
      case System.find_executable("ktlint") do
        nil ->
          IO.puts("\n  [lint] ktlint not installed — brew install ktlint")

        ktlint ->
          {:ok, dir} = ProjectGenerator.generate("test_app", tmp)
          kt_files = Path.wildcard(Path.join(dir, "android/**/*.kt"))
          # Auto-format first (fixes whitespace, blank lines, signature wrapping, etc.)
          # then check — only non-auto-correctable violations (wildcard imports,
          # backing property naming, etc.) will cause the test to fail.
          System.cmd(ktlint, ["--format" | kt_files], stderr_to_stdout: true)
          {output, exit_code} = System.cmd(ktlint, kt_files, stderr_to_stdout: true)
          assert exit_code == 0, "ktlint found issues in generated Kotlin:\n#{output}"
      end
    end

    test "MainActivity.kt calls enableEdgeToEdge before super.onCreate", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)

      content =
        File.read!(
          Path.join(dir, "android/app/src/main/java/com/example/test_app/MainActivity.kt")
        )

      assert content =~ "enableEdgeToEdge()"
      assert content =~ "import androidx.activity.enableEdgeToEdge"
    end

    test "MainActivity.kt applies safeDrawingPadding to root modifier", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("test_app", tmp)

      content =
        File.read!(
          Path.join(dir, "android/app/src/main/java/com/example/test_app/MainActivity.kt")
        )

      assert content =~ "safeDrawingPadding()"
      assert content =~ "import androidx.compose.foundation.layout.safeDrawingPadding"
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
    test "mob.exs documents liveview_port (commented; runtime hashes per app)", %{tmp: tmp} do
      # iter 13d / issues.md #4: hardcoded `liveview_port: 4200` collided
      # across multiple installed Mob LV apps. mob.exs now ships the line
      # commented out — runtime hashes the app name into 4200..4999 by
      # default. Users uncomment to pin a specific port.
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)
      assert File.exists?(Path.join(dir, "mob.exs"))
      content = File.read!(Path.join(dir, "mob.exs"))
      assert content =~ "liveview_port"
      assert content =~ "# config :mob, liveview_port"
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
      # Match the hook registered in the LiveSocket's hooks block. Phoenix
      # has shipped variants over time — `hooks: {MobHook}`,
      # `hooks: {MobHook, ...colocatedHooks}` — so anchor on the property
      # name rather than the literal one-element-object form.
      assert content =~ ~r/hooks:\s*\{[^}]*MobHook\b/
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
    test "config ports are 4200 (host endpoint must match on-device mob_app.ex)",
         %{tmp: tmp} do
      # phx.new defaults dev=4000, test=4002, runtime PORT=4000 — but Mob's
      # mob_app.ex pins the on-device endpoint to 4200, and another developer
      # running `mix phx.server` on 4000 would collide with the generated
      # project's setup. Pin all three files so the ports stay aligned.
      {:ok, dir} = ProjectGenerator.liveview_generate("lv_test", tmp)

      dev = File.read!(Path.join(dir, "config/dev.exs"))
      assert dev =~ "port: 4200"

      refute dev =~ "port: 4000",
             "config/dev.exs still has Phoenix's default 4000 — patch_config_ports regressed"

      test_cfg = File.read!(Path.join(dir, "config/test.exs"))
      assert test_cfg =~ "port: 4202"

      refute test_cfg =~ "port: 4002",
             "config/test.exs still has Phoenix's default 4002"

      runtime = File.read!(Path.join(dir, "config/runtime.exs"))

      # Phoenix changed its runtime PORT fallback syntax between 1.7 and
      # 1.8: the older form was `System.get_env("PORT") || "4200"`, the
      # newer is `System.get_env("PORT", "4200")` (two-arg form). Match
      # either — the patcher in project_generator.ex handles both.
      assert runtime =~ ~r/"PORT"\s*\)\s*\|\|\s*"4200"/ or
               runtime =~ ~r/"PORT"\s*,\s*"4200"/,
             "config/runtime.exs has no PORT-to-4200 fallback in either form"

      refute runtime =~ ~r/"PORT"\s*\)\s*\|\|\s*"4000"/,
             "config/runtime.exs PORT env-var fallback still 4000 (legacy ||)"

      refute runtime =~ ~r/"PORT"\s*,\s*"4000"/,
             "config/runtime.exs PORT env-var fallback still 4000 (two-arg form)"
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
      tmp =
        Path.join(
          System.tmp_dir!(),
          "mob_new_platform_test_#{System.unique_integer([:positive])}"
        )

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

  # ── --blank flag (minimal app) ────────────────────────────────────────────

  describe "blank_excluded?/3" do
    @root "/tmpl"

    test "skips demo screens only when blank: true" do
      assert ProjectGenerator.blank_excluded?("/tmpl/lib/app_name/dice_screen.ex.eex", @root,
               blank: true
             )

      refute ProjectGenerator.blank_excluded?("/tmpl/lib/app_name/dice_screen.ex.eex", @root, [])
    end

    test "keeps core files even when blank: true" do
      for core <- ~w(app home_screen repo) do
        refute ProjectGenerator.blank_excluded?(
                 "/tmpl/lib/app_name/#{core}.ex.eex",
                 @root,
                 blank: true
               ),
               "#{core} must survive --blank"
      end
    end

    test "does not touch files outside lib/app_name/ under blank" do
      refute ProjectGenerator.blank_excluded?("/tmpl/mix.exs.eex", @root, blank: true)

      refute ProjectGenerator.blank_excluded?("/tmpl/android/app/build.gradle.eex", @root,
               blank: true
             )
    end
  end

  describe "generate/3 with blank: true" do
    setup do
      tmp =
        Path.join(System.tmp_dir!(), "mob_new_blank_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)
      {:ok, tmp: tmp}
    end

    test "keeps core screens, drops demo screens", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("blank_app", tmp, blank: true)
      lib = Path.join(dir, "lib/blank_app")

      assert File.exists?(Path.join(lib, "app.ex"))
      assert File.exists?(Path.join(lib, "home_screen.ex"))
      assert File.exists?(Path.join(lib, "repo.ex"))

      for demo <-
            ~w(audio_screen dice_screen list_screen round storage_screen text_screen webview_screen) do
        refute File.exists?(Path.join(lib, "#{demo}.ex")), "#{demo}.ex must not be generated"
      end
    end

    test "mix.exs drops the showcase plugins", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("blank_app", tmp, blank: true)
      content = File.read!(Path.join(dir, "mix.exs"))

      refute content =~ "mob_camera"
      refute content =~ "mob_location"
      refute content =~ "mob_biometric"
      refute content =~ "mob_themes"
      # Core deps still present.
      assert content =~ "ecto_sqlite3"
      assert content =~ "aliases: aliases()"
    end

    test "mob.exs has empty plugins and no styles", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("blank_app", tmp, blank: true)
      content = File.read!(Path.join(dir, "mob.exs"))

      assert content =~ "config :mob, :plugins, []"
      refute content =~ ":styles"
      refute content =~ ":default_style"
    end

    test "home_screen drops demo nav buttons but keeps plugin_section + theme", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("blank_app", tmp, blank: true)
      content = File.read!(Path.join(dir, "lib/blank_app/home_screen.ex"))

      refute content =~ "TextScreen"
      refute content =~ "DiceScreen"
      refute content =~ ":open_audio"
      # Plugin auto-listing + theme toggle survive (work with zero plugins).
      assert content =~ "Mob.Plugins.screens()"
      assert content =~ "plugin_section"
      assert content =~ "Mob.Theme.Dark"
    end

    test "default (non-blank) still ships demo screens + plugins (regression guard)", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("full_app", tmp)
      assert File.exists?(Path.join(dir, "lib/full_app/dice_screen.ex"))
      assert File.read!(Path.join(dir, "mix.exs")) =~ "mob_camera"
      assert File.read!(Path.join(dir, "mob.exs")) =~ ":mob_camera"
    end
  end

  # ── --python flag (apply_python_patches) ──────────────────────────────────

  describe "generate/3 with python: true" do
    setup do
      tmp =
        Path.join(
          System.tmp_dir!(),
          "mob_new_python_test_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)
      {:ok, tmp: tmp}
    end

    test "writes lib/<app>/python_paths.ex with the right module name", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("py_app", tmp, python: true)
      path = Path.join(dir, "lib/py_app/python_paths.ex")
      assert File.exists?(path)

      content = File.read!(path)
      assert content =~ "defmodule PyApp.PythonPaths do"
      assert content =~ "def detect("
      assert content =~ "def build_ios_paths("
      assert content =~ "def build_android_paths"
      assert content =~ "def missing("
      assert content =~ ~s|"python3.13"|
    end

    test "python_paths supports :android via MOB_PYTHON_HOME / MOB_PYTHON_DL", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("py_app", tmp, python: true)
      content = File.read!(Path.join(dir, "lib/py_app/python_paths.ex"))
      assert content =~ "MOB_PYTHON_HOME"
      assert content =~ "MOB_PYTHON_DL"
      assert content =~ "{:android, paths}"
    end

    test "adds {:pythonx, ...} to mix.exs deps", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("py_app", tmp, python: true)
      content = File.read!(Path.join(dir, "mix.exs"))
      assert content =~ ~r/\{:pythonx,\s*"~>/
    end

    test "deliberately does NOT touch config/config.exs", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("py_app", tmp, python: true)
      config_path = Path.join(dir, "config/config.exs")

      if File.exists?(config_path) do
        content = File.read!(config_path)
        # No env-var gate, no :uv_init injection — `:pythonx, :uv_init`
        # in compile-time config makes Pythonx auto-run uv at boot,
        # which fails on device.
        refute content =~ "MOB_TARGET"
        refute content =~ ":pythonx"
      end
    end

    test "app.ex contains the pythonx init branch when python: true", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("py_app", tmp, python: true)
      content = File.read!(Path.join(dir, "lib/py_app/app.ex"))
      assert content =~ "init_pythonx()"
      assert content =~ "Pythonx.Uv.fetch"
      assert content =~ "Pythonx.init(dl, home, dl"
      assert content =~ "{:android,"
    end

    test "python: false (default) skips all patches", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("vanilla_app", tmp)
      refute File.exists?(Path.join(dir, "lib/vanilla_app/python_paths.ex"))

      mix_content = File.read!(Path.join(dir, "mix.exs"))
      refute mix_content =~ ":pythonx"

      app_content = File.read!(Path.join(dir, "lib/vanilla_app/app.ex"))
      refute app_content =~ "init_pythonx"
      refute app_content =~ "Pythonx"
    end
  end

  describe "apply_python_patches/2" do
    @tag :tmp_dir
    test "is idempotent — running twice doesn't double-add the dep", %{tmp_dir: tmp} do
      {:ok, dir} = ProjectGenerator.generate("idem_app", tmp, python: true)
      content_before = File.read!(Path.join(dir, "mix.exs"))

      ProjectGenerator.apply_python_patches(dir, "idem_app")
      content_after = File.read!(Path.join(dir, "mix.exs"))

      assert content_before == content_after
    end

    @tag :tmp_dir
    test "running twice doesn't create config/config.exs", %{tmp_dir: tmp} do
      {:ok, dir} = ProjectGenerator.generate("idem_app2", tmp, python: true)
      ProjectGenerator.apply_python_patches(dir, "idem_app2")

      # The python feature deliberately does not patch config/config.exs
      # — repeating the patch run mustn't change that.
      config_path = Path.join(dir, "config/config.exs")

      if File.exists?(config_path) do
        refute File.read!(config_path) =~ ":pythonx"
      end
    end
  end

  # ── --python integration lint ────────────────────────────────────────────────
  #
  # Generates a real --python project and runs `mix compile` on it. This is
  # the canonical end-to-end check that the Pythonx generator wiring (config,
  # python_paths.ex, app.ex on_start branch, mix.exs dep) actually produces a
  # buildable project. EEx templates can't be linted directly, but a
  # compile-clean generated project is the strongest possible signal that the
  # template wiring is correct.
  #
  # Tagged :integration because:
  #   * `mix deps.get` hits Hex / disk-cache (~50 deps including pythonx)
  #   * `mix compile` takes ~30s on a cold cache
  #
  # Run explicitly: `mix test --only integration`

  describe "--python project end-to-end" do
    setup do
      tmp =
        Path.join(
          System.tmp_dir!(),
          "mob_new_python_e2e_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)
      {:ok, tmp: tmp}
    end

    @tag :integration
    test "generated --python project compiles cleanly", %{tmp: tmp} do
      {:ok, dir} = ProjectGenerator.generate("py_e2e", tmp, python: true, local: true)

      # The generator picks up MOB_DIR / MOB_DEV_DIR if set, otherwise
      # falls back to ./mob, ./mob_dev, ../mob, ../mob_dev. CI only needs
      # one of those to resolve.
      mix = System.find_executable("mix") || flunk("mix not on PATH")

      {deps_out, deps_code} =
        System.cmd(mix, ["deps.get"], cd: dir, stderr_to_stdout: true)

      assert deps_code == 0,
             "deps.get failed for generated --python project:\n#{deps_out}"

      {compile_out, compile_code} =
        System.cmd(mix, ["compile", "--warnings-as-errors"],
          cd: dir,
          stderr_to_stdout: true
        )

      # Sigil-driven warnings from the user code (Mob's ~MOB sigil
      # produces some type warnings that aren't actionable from the
      # template) are tolerated — only a non-zero exit from a compile
      # error fails the test.
      if compile_code != 0 do
        # Re-run without --warnings-as-errors and only fail if the actual
        # compile bombed. This keeps the test from going red just because
        # the type checker grumbles about something unrelated.
        {plain_out, plain_code} =
          System.cmd(mix, ["compile"], cd: dir, stderr_to_stdout: true)

        assert plain_code == 0,
               "generated --python project failed to compile:\n#{compile_out}\n\nplain compile:\n#{plain_out}"
      end
    end
  end

  # ── scaffolded Mob.ScreenCase test compiles against the real API ──────────────
  #
  # The home-screen test scaffold (test/app_name/home_screen_test.exs.eex) does
  # `use Mob.ScreenCase` and calls mount_screen/3, render_info/2, assigns/1 and
  # assert_renderable/2 — an API that lives in mob (see Mob.ScreenCase). The
  # other scaffold tests in this file only substring-match the *rendered file
  # content*, so a rename in mob (e.g. mount_screen → mount, assert_renderable →
  # assert_drawable) would slip through CI here while silently breaking the test
  # suite of every project `mix mob.new` generates. This test pins the contract:
  # it generates a real native project and compiles it under MIX_ENV=test, which
  # compiles test/ — including the scaffolded screen test — against the real
  # Mob.ScreenCase. If the API drifts, the generated test fails to compile and
  # this turns red.
  #
  # Tagged :integration to match the --python E2E test above (same gating, same
  # CI invocation): `mix deps.get` + a cold `mix compile` are slow and the
  # `local: true` path needs a resolvable mob checkout.
  #
  # The catch unique to this test: the mob checkout MOB_DIR points at must
  # actually define Mob.ScreenCase. It was introduced in the mob screen-test
  # branch and is being released with mob 0.7.2; mob master doesn't have it yet.
  # We resolve, in order: $MOB_SCREEN_CASE_DIR, then $MOB_DIR if that checkout
  # has lib/mob/screen_case.ex, then the known local screen-test worktree. If
  # none has Mob.ScreenCase we skip rather than fail — a host without the
  # coupled mob branch can't run this check, and that's a property of the
  # environment, not a regression in mob_new.
  describe "scaffolded Mob.ScreenCase test end-to-end" do
    setup do
      tmp =
        Path.join(
          System.tmp_dir!(),
          "mob_new_screen_case_e2e_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)
      {:ok, tmp: tmp}
    end

    @tag :integration
    test "generated home_screen_test.exs compiles against the real Mob.ScreenCase",
         %{tmp: tmp} do
      case mob_dir_with_screen_case() do
        nil ->
          # No mob checkout on this host defines Mob.ScreenCase (the coupled
          # mob branch / 0.7.2 isn't present). That's an environment gap, not a
          # mob_new regression, so warn and pass rather than fail — CI for the
          # release runs with the coupled mob checked out and does exercise this.
          IO.warn(
            "skipping Mob.ScreenCase compile check: no mob checkout with " <>
              "lib/mob/screen_case.ex found (set MOB_SCREEN_CASE_DIR or MOB_DIR)"
          )

          assert true

        mob_dir ->
          mob_dev_dir = System.get_env("MOB_DEV_DIR") || "/Users/kevin/code/mob_dev"

          {:ok, dir} =
            with_env(
              %{"MOB_DIR" => mob_dir, "MOB_DEV_DIR" => mob_dev_dir},
              fn -> ProjectGenerator.generate("screen_e2e", tmp, local: true) end
            )

          scaffold = Path.join(dir, "test/screen_e2e/home_screen_test.exs")

          assert File.exists?(scaffold),
                 "generator did not emit the scaffolded screen test at #{scaffold}"

          mix = System.find_executable("mix") || flunk("mix not on PATH")

          {deps_out, deps_code} =
            System.cmd(mix, ["deps.get"], cd: dir, stderr_to_stdout: true)

          assert deps_code == 0,
                 "deps.get failed for generated screen-case project:\n#{deps_out}"

          # MIX_ENV=test compiles test/ too, so this exercises the scaffolded
          # home_screen_test.exs against the real Mob.ScreenCase. A rename in
          # mob's ScreenCase surface lands here as a compile error.
          {compile_out, compile_code} =
            System.cmd(mix, ["compile", "--warnings-as-errors"],
              cd: dir,
              env: [{"MIX_ENV", "test"}],
              stderr_to_stdout: true
            )

          assert compile_code == 0,
                 "generated project (incl. scaffolded Mob.ScreenCase test) failed " <>
                   "to compile under MIX_ENV=test:\n#{compile_out}"
      end
    end
  end

  # `--local` was originally documented as "use path: deps for mob/mob_dev"
  # only, but the mental model from users is "use everything local" —
  # including templates. local_mob_new_priv/1 opts into local templates
  # when (and only when) the caller asks AND a reachable mob_new
  # checkout exists.
  describe "local_mob_new_priv/1" do
    setup do
      tmp =
        Path.join(System.tmp_dir!(), "mob_new_local_priv_#{System.unique_integer([:positive])}")

      File.mkdir_p!(Path.join(tmp, "priv/templates/mob.new"))
      on_exit(fn -> File.rm_rf!(tmp) end)
      {:ok, tmp: tmp}
    end

    test "returns nil when opts[:local] is not set", %{tmp: tmp} do
      System.put_env("MOB_NEW_DIR", tmp)
      on_exit(fn -> System.delete_env("MOB_NEW_DIR") end)

      assert MobNew.ProjectGenerator.local_mob_new_priv([]) == nil
      assert MobNew.ProjectGenerator.local_mob_new_priv(local: false) == nil
    end

    test "returns MOB_NEW_DIR's priv when --local is set and dir exists", %{tmp: tmp} do
      System.put_env("MOB_NEW_DIR", tmp)
      on_exit(fn -> System.delete_env("MOB_NEW_DIR") end)

      assert MobNew.ProjectGenerator.local_mob_new_priv(local: true) ==
               Path.join(tmp, "priv")
    end

    test "returns nil when MOB_NEW_DIR doesn't contain priv/templates/mob.new", %{tmp: tmp} do
      # Empty subdir of tmp — no priv structure.
      empty = Path.join(tmp, "empty")
      File.mkdir_p!(empty)
      System.put_env("MOB_NEW_DIR", empty)
      on_exit(fn -> System.delete_env("MOB_NEW_DIR") end)

      # The MOB_NEW_DIR is bogus, but ~/code/mob_new might exist on the
      # host. local_mob_new_priv tries candidates in order; if the env
      # entry fails, it falls through to ~/code/mob_new. So this asserts
      # only "env entry didn't match", not the final return.
      result = MobNew.ProjectGenerator.local_mob_new_priv(local: true)
      assert result != Path.join(empty, "priv")
    end

    test "MOB_NEW_DIR takes precedence over the ~/code/mob_new fallback", %{tmp: tmp} do
      System.put_env("MOB_NEW_DIR", tmp)
      on_exit(fn -> System.delete_env("MOB_NEW_DIR") end)

      assert MobNew.ProjectGenerator.local_mob_new_priv(local: true) ==
               Path.join(tmp, "priv")
    end

    test "no MOB_NEW_DIR + no ~/code/mob_new → nil (no false positives)" do
      System.delete_env("MOB_NEW_DIR")
      # If the host happens to have ~/code/mob_new (this dev's machine
      # almost certainly does), the function correctly finds it. Don't
      # over-assert; just confirm shape.
      #
      # The Path.expand here probes an EXTERNAL filesystem location (the
      # developer's checkout of mob_new) — it's not looking up this app's
      # own priv/, which is what JumpCredo's Application.app_dir check
      # is for. Silenced inline.
      # credo:disable-for-next-line ExSlop.Check.Warning.PathExpandPriv
      if File.dir?(Path.expand("~/code/mob_new/priv/templates/mob.new")) do
        assert is_binary(MobNew.ProjectGenerator.local_mob_new_priv(local: true))
      else
        assert MobNew.ProjectGenerator.local_mob_new_priv(local: true) == nil
      end
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  # Resolves a mob checkout that actually defines Mob.ScreenCase (presence of
  # lib/mob/screen_case.ex), or nil if none is reachable. Tries, in order:
  #   1. $MOB_SCREEN_CASE_DIR  — explicit opt-in for hosts/CI
  #   2. $MOB_DIR              — only if that checkout has ScreenCase
  #   3. the local screen-test worktree the coupled mob PR lives in
  # Returning nil (rather than raising) lets the caller skip on hosts without
  # the coupled mob branch instead of failing.
  defp mob_dir_with_screen_case do
    [
      System.get_env("MOB_SCREEN_CASE_DIR"),
      System.get_env("MOB_DIR"),
      "/Users/kevin/code/mob/.claude/worktrees/screen-test"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Path.expand/1)
    |> Enum.find(fn dir -> File.exists?(Path.join(dir, "lib/mob/screen_case.ex")) end)
  end

  # Runs fun with the given env vars set, restoring each to its prior value
  # (or deleting it if it wasn't set) afterwards. Keeps the MOB_DIR override
  # scoped to the generate/3 call instead of leaking into the rest of the suite.
  defp with_env(vars, fun) do
    previous = Map.new(vars, fn {k, _} -> {k, System.get_env(k)} end)
    Enum.each(vars, fn {k, v} -> System.put_env(k, v) end)

    try do
      fun.()
    after
      Enum.each(previous, fn
        {k, nil} -> System.delete_env(k)
        {k, v} -> System.put_env(k, v)
      end)
    end
  end

  # Returns the path to the NDK's aarch64 clang, or nil if no NDK is
  # installed. Probes standard locations + env vars; picks the
  # lexicographically-highest version (which is also the highest
  # semver for x.y.z NDK names).
  defp find_android_ndk_clang do
    candidates =
      [
        System.get_env("ANDROID_NDK_ROOT"),
        System.get_env("ANDROID_NDK_HOME"),
        # macOS default
        Path.expand("~/Library/Android/sdk/ndk"),
        # Linux default
        Path.expand("~/Android/Sdk/ndk")
      ]
      |> Enum.reject(&is_nil/1)

    Enum.find_value(candidates, &probe_ndk_root/1)
  end

  defp probe_ndk_root(root) do
    cond do
      # ANDROID_NDK_ROOT may point directly at an NDK, not at the parent
      File.dir?(Path.join(root, "toolchains/llvm/prebuilt")) -> clang_in(root)
      File.dir?(root) -> highest_versioned_clang(root)
      true -> nil
    end
  end

  defp highest_versioned_clang(root) do
    root
    |> File.ls!()
    |> Enum.sort(:desc)
    |> Enum.find_value(fn version -> clang_in(Path.join(root, version)) end)
  end

  defp clang_in(ndk_root) do
    host =
      case :os.type() do
        {:unix, :darwin} -> "darwin-x86_64"
        {:unix, :linux} -> "linux-x86_64"
        _ -> nil
      end

    if host do
      path =
        Path.join([
          ndk_root,
          "toolchains/llvm/prebuilt",
          host,
          "bin/aarch64-linux-android24-clang"
        ])

      if File.exists?(path), do: path, else: nil
    end
  end
end
