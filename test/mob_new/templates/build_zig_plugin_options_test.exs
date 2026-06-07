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
  @android_plugin_options ~w(plugin_c_nifs plugin_zig_nifs plugin_jni_sources)

  @template Path.expand(
              "../../../priv/templates/mob.new/android/app/src/main/jni/build.zig.eex",
              __DIR__
            )

  test "every Android plugin -D flag mob_dev emits is declared as a b.option" do
    src = File.read!(@template)

    for opt <- @android_plugin_options do
      assert src =~ ~r/b\.option\([^)]*"#{opt}"/,
             "build.zig.eex must declare `b.option(..., \"#{opt}\", ...)` — mob_dev " <>
               "passes -D#{opt} to it; an undeclared option makes zig abort the build."
    end
  end
end
