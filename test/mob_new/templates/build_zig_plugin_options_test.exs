defmodule MobNew.Templates.BuildZigPluginOptionsTest do
  use ExUnit.Case, async: true

  # Drift guard. mob_dev's MobDev.NativeBuild emits these `-D<flag>=...` args to
  # the generated Android JNI build.zig, each gated only on the value being
  # non-empty. If the shipped template doesn't DECLARE a `b.option` for a flag,
  # zig 0.16 rejects the unknown `-D` option and the native Android build of a
  # freshly-generated app aborts the moment a plugin makes that flag non-empty
  # (e.g. activating a `lang: :zig` NIF populates plugin_zig_nifs). This caught
  # exactly that gap: the template had only plugin_c_nifs while mob_dev had grown
  # plugin_zig_nifs + plugin_jni_sources. Keep this list in sync with the flags
  # native_build can emit to the Android zig build.
  @android_plugin_options ~w(plugin_c_nifs plugin_zig_nifs plugin_jni_sources plugin_static_libs)

  @template Path.expand(
              "../../../priv/templates/mob.new/android/app/src/main/jni/build.zig.eex",
              __DIR__
            )

  # mob_dev also passes -Dplugin_static_libs to BOTH iOS sim and iOS device
  # builds, so each iOS template must DECLARE the option or zig aborts a plugin
  # build (a cpp_archive plugin populates it) exactly as on Android. Without
  # this guard an iOS template silently losing the option would break plugin
  # builds with no test catching it.
  @ios_dir Path.expand("../../../priv/templates/mob.new/ios", __DIR__)
  @ios_templates [
    Path.join(@ios_dir, "build.zig.eex"),
    Path.join(@ios_dir, "build_device.zig.eex")
  ]

  test "every Android plugin -D flag mob_dev emits is declared as a b.option" do
    src = File.read!(@template)

    for opt <- @android_plugin_options do
      assert src =~ ~r/b\.option\([^)]*"#{opt}"/,
             "build.zig.eex must declare `b.option(..., \"#{opt}\", ...)` — mob_dev " <>
               "passes -D#{opt} to it; an undeclared option makes zig abort the build."
    end
  end

  test "iOS build templates declare the plugin_static_libs b.option" do
    for tmpl <- @ios_templates do
      src = File.read!(tmpl)
      base = Path.basename(tmpl)

      assert src =~ ~r/b\.option\([^)]*"plugin_static_libs"/,
             "#{base}: must declare `b.option(..., \"plugin_static_libs\", ...)` — " <>
               "mob_dev passes -Dplugin_static_libs to both iOS sim and device builds; " <>
               "an undeclared option makes zig abort a plugin (cpp_archive) build."
    end
  end
end
