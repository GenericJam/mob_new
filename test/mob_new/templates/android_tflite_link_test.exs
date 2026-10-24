defmodule MobNew.Templates.AndroidTfliteLinkTest do
  # MOB-394: mob_dev passes `-Dtflite_static=true -Dtflite_lib=<libtflite_nif.a>`
  # when nx_tflite_mob is in deps, and the driver table then references
  # `tflite_nif_nif_init`. The template accepted `tflite_lib` but never linked
  # it, so every such app died at launch with "cannot locate symbol
  # tflite_nif_nif_init". This runs the generated build.zig for real, with a
  # stand-in NDK clang that records its arguments, and checks what reaches
  # the lib<app>.so link.
  use ExUnit.Case, async: true

  alias MobNew.ProjectGenerator

  if System.find_executable("zig") == nil do
    @moduletag skip: "zig not on PATH"
  end

  # A cold zig cache (CI) compiles the target's libc and compiler_rt first.
  @moduletag timeout: :timer.minutes(5)

  @abi "arm64-v8a"

  setup do
    tmp = Path.join(System.tmp_dir!(), "android_link_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, project} = ProjectGenerator.generate("tfl_app", tmp)
    # mob_dev creates this before the zig build (it copies
    # libtensorflowlite_jni.so there); the link's install step writes into it.
    File.mkdir_p!(Path.join(project, "android/app/src/main/jniLibs/#{@abi}"))
    %{tmp: tmp, project: project, stubs: write_stubs(tmp)}
  end

  test "TFLite enabled: the NIF archive and libtensorflowlite_jni are linked into lib<app>.so",
       ctx do
    archive = Path.join(ctx.tmp, "libtflite_nif.a")
    File.write!(archive, "")

    link = main_link_args(ctx, ["-Dtflite_static=true", "-Dtflite_lib=#{archive}"])

    assert archive in link
    assert "-L#{Path.join(ctx.project, "android/app/src/main/jniLibs/#{@abi}")}" in link
    assert "-ltensorflowlite_jni" in link
  end

  test "TFLite not enabled: no TFLite archive or runtime on the link line", ctx do
    link = main_link_args(ctx, [])

    refute Enum.any?(link, &String.ends_with?(&1, "libtflite_nif.a"))
    refute Enum.any?(link, &String.contains?(&1, "tensorflowlite"))
  end

  # Runs `zig build native-lib` against the generated build.zig and returns
  # the argument list of the clang call that produces lib<app>.so.
  defp main_link_args(ctx, extra) do
    s = ctx.stubs
    jni = Path.join(ctx.project, "android/app/src/main/jni")
    log = Path.join(ctx.tmp, "clang.log")

    args =
      [
        "build",
        "native-lib",
        "-Dabi=#{@abi}",
        "-Dotp_dir=#{s.otp}",
        "-Derts_vsn=erts-0",
        "-Dmob_dir=#{s.mob}",
        "-Ddriver_tab=#{s.driver_tab}",
        "-Dproject_jni_dir=#{s.jni}",
        "-Dndk_sysroot=#{s.sysroot}",
        "-Dapp_name=tfl_app",
        "-Dproject_root=#{ctx.project}",
        "-Dexqlite_src=#{s.exqlite}",
        "--cache-dir",
        Path.join(ctx.tmp, "zig-cache")
      ] ++ extra

    {out, status} =
      System.cmd("zig", args, cd: jni, env: [{"CLANG_LOG", log}], stderr_to_stdout: true)

    assert status == 0, "zig build native-lib failed:\n#{out}"

    log
    |> File.read!()
    |> String.split("---\n", trim: true)
    |> Enum.map(&String.split(&1, "\n", trim: true))
    |> Enum.find(&("-Wl,-soname,libtfl_app.so" in &1))
    |> Kernel.||(flunk("no lib<app>.so link call in the clang log"))
  end

  # Minimal stand-ins: tiny sources the build compiles for real, an empty OTP
  # tree (the link is faked), and an NDK clang that logs each invocation's
  # arguments and touches its -o output.
  defp write_stubs(tmp) do
    root = Path.join(tmp, "stubs")
    mob = Path.join(root, "mob")
    jni = Path.join(root, "jni")
    otp = Path.join(root, "otp")
    exqlite = Path.join(root, "exqlite")
    sysroot = Path.join(root, "ndk/sysroot")
    clang = Path.join(root, "ndk/bin/clang")

    for dir <- [Path.join(mob, "android/jni"), jni, Path.join(otp, "erts-0/include"), exqlite] do
      File.mkdir_p!(dir)
    end

    File.mkdir_p!(sysroot)
    File.mkdir_p!(Path.dirname(clang))

    driver_tab = Path.join(jni, "driver_tab_android.zig")
    File.write!(driver_tab, "export fn driver_tab_stub() void {}\n")
    File.write!(Path.join(mob, "android/jni/mob_nif.zig"), "export fn mob_nif_stub() void {}\n")
    File.write!(Path.join(mob, "android/jni/mob_beam.zig"), "export fn mob_beam_stub() void {}\n")
    File.write!(Path.join(jni, "beam_jni.c"), "int beam_jni_stub(void) { return 0; }\n")
    File.write!(Path.join(exqlite, "sqlite3_nif.c"), "int sqlite3_nif_stub(void) { return 0; }\n")
    File.write!(Path.join(exqlite, "sqlite3.c"), "int sqlite3_stub(void) { return 0; }\n")

    File.write!(clang, """
    #!/bin/sh
    printf '%s\\n' "$@" >> "$CLANG_LOG"
    printf -- '---\\n' >> "$CLANG_LOG"
    prev=
    for a in "$@"; do
      if [ "$prev" = "-o" ]; then : > "$a"; fi
      prev=$a
    done
    """)

    File.chmod!(clang, 0o755)

    %{
      mob: mob,
      jni: jni,
      otp: otp,
      exqlite: exqlite,
      sysroot: sysroot,
      driver_tab: driver_tab
    }
  end
end
