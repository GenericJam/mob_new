defmodule MobNew.Templates.AndroidFloatAbiTest do
  # MOB-522: Zig treats arm-linux-androideabi as a soft-float ABI, so without
  # `-mfloat-abi=softfp` clang lowered every float op in the armeabi-v7a C
  # objects to a compiler-rt call (__aeabi_fmul, __aeabi_dadd, ...). Magpie's
  # mixer took 298 % of real time on a moto e; with VFP, 53 %. This runs the
  # generated build.zig for real, with a stand-in NDK clang for the links,
  # and inspects the C objects it compiled for each flag set: the core flags
  # (beam_jni.c), the per-NIF flags (a project C NIF) and the SQLite flags.
  use ExUnit.Case, async: true

  alias MobNew.ProjectGenerator

  if System.find_executable("zig") == nil do
    @moduletag skip: "zig not on PATH"
  end

  # A cold zig cache (CI) compiles the target's libc and compiler_rt first.
  @moduletag timeout: :timer.minutes(5)

  @abi "armeabi-v7a"

  # Exported and fed by parameters, so -Os can't fold the arithmetic away.
  @float_c """
  float FN_f(float a, float b) { return a * b + a / b; }
  double FN_d(double a, double b) { return a * b + a / b; }
  """

  # Soft-float lowering calls these (the AEABI names, or the libgcc ones).
  @soft_float_helpers ~r/__aeabi_[fd](add|sub|mul|div)|__(add|sub|mul|div)[sd]f3/

  setup do
    tmp = Path.join(System.tmp_dir!(), "android_float_abi_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, project} = ProjectGenerator.generate("fp_app", tmp)
    File.mkdir_p!(Path.join(project, "android/app/src/main/jniLibs/#{@abi}"))
    File.mkdir_p!(Path.join(project, "c_src"))
    File.write!(Path.join(project, "c_src/fp_nif.c"), float_source("fp_nif"))
    %{tmp: tmp, project: project, stubs: write_stubs(tmp)}
  end

  test "armeabi-v7a C objects do float math in VFP, not soft-float helper calls", ctx do
    objects = linked_objects(ctx)

    for prefix <- ["beam_jni", "fp_nif", "sqlite3"] do
      name = "#{prefix}.o"

      path =
        Enum.find(objects, &(Path.basename(&1) == name)) ||
          flunk("#{name} not on any link line: #{inspect(objects)}")

      obj = File.read!(path)

      # Machine code holding the float functions, or the helper check is vacuous.
      assert <<0x7F, "ELF", _::binary>> = obj
      assert obj =~ "#{prefix}_f" and obj =~ "#{prefix}_d", "#{name} lacks the float functions"

      helpers = Regex.scan(@soft_float_helpers, obj) |> Enum.map(&hd/1)

      assert helpers == [],
             "#{name} calls soft-float helpers #{inspect(Enum.uniq(helpers))}: " <>
               "the armeabi-v7a flags lack -mfloat-abi=softfp"
    end
  end

  # Runs `zig build native-lib` for armeabi-v7a and returns every object
  # path handed to the two .so links (lib<app>.so and libsqlite3_nif.so).
  defp linked_objects(ctx) do
    s = ctx.stubs
    jni = Path.join(ctx.project, "android/app/src/main/jni")
    log = Path.join(ctx.tmp, "clang.log")

    args = [
      "build",
      "native-lib",
      "-Dabi=#{@abi}",
      "-Dotp_dir=#{s.otp}",
      "-Derts_vsn=erts-0",
      "-Dmob_dir=#{s.mob}",
      "-Ddriver_tab=#{s.driver_tab}",
      "-Dproject_jni_dir=#{s.jni}",
      "-Dndk_sysroot=#{s.sysroot}",
      "-Dapp_name=fp_app",
      "-Dproject_root=#{ctx.project}",
      "-Dexqlite_src=#{s.exqlite}",
      "-Dproject_c_nifs=fp_nif",
      "--cache-dir",
      Path.join(ctx.tmp, "zig-cache")
    ]

    {out, status} =
      System.cmd("zig", args, cd: jni, env: [{"CLANG_LOG", log}], stderr_to_stdout: true)

    assert status == 0, "zig build native-lib failed:\n#{out}"

    log
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.filter(&String.ends_with?(&1, ".o"))
  end

  defp float_source(prefix), do: String.replace(@float_c, "FN", prefix)

  # Stand-ins: the C sources carry float math and compile for real; the zig
  # ones are stubs (Zig's own codegen is soft-float for this target either
  # way); an empty OTP tree and an NDK clang that logs each invocation's
  # arguments and touches its -o output, since the links are faked.
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
    File.write!(Path.join(jni, "beam_jni.c"), float_source("beam_jni"))
    File.write!(Path.join(exqlite, "sqlite3_nif.c"), "int sqlite3_nif_stub(void) { return 0; }\n")
    File.write!(Path.join(exqlite, "sqlite3.c"), float_source("sqlite3"))

    File.write!(clang, """
    #!/bin/sh
    printf '%s\\n' "$@" >> "$CLANG_LOG"
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
