defmodule MobNew.Templates.IosTfliteLinkTest do
  # MOB-394: mob_dev passes `-Dtflite_static=true -Dtflite_dir=<dir of
  # libtflite_nif.a> -Dtflite_framework_dir=<TensorFlowLiteC Frameworks/>` to
  # the iOS builds when nx_tflite_mob is in deps, and the driver table then
  # references `tflite_nif_nif_init`. Both iOS templates accepted those options
  # and dropped them. This runs each generated build.zig for real, with a
  # stand-in `xcrun` that records its arguments, and checks what reaches the
  # final link: the NIF archive plus the TensorFlowLiteC / Core ML delegate
  # frameworks from the slice for that SDK.
  use ExUnit.Case, async: true

  alias MobNew.ProjectGenerator

  # zig resolves the iOS SDK through xcrun to compile the C objects, so this
  # needs a Mac with Xcode as well as zig.
  cond do
    System.find_executable("zig") == nil -> @moduletag skip: "zig not on PATH"
    System.find_executable("xcrun") == nil -> @moduletag skip: "xcrun not on PATH (needs Xcode)"
    true -> :ok
  end

  setup do
    tmp = Path.join(System.tmp_dir!(), "ios_link_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, project} = ProjectGenerator.generate("tfl_app", tmp)
    %{tmp: tmp, project: project, stubs: write_stubs(tmp)}
  end

  for {template, slice} <- [
        {"build.zig", "ios-arm64_x86_64-simulator"},
        {"build_device.zig", "ios-arm64"}
      ] do
    test "#{template}: TFLite enabled links libtflite_nif.a and the #{slice} TensorFlowLiteC slice",
         ctx do
      lib_dir = Path.join(ctx.tmp, "tflite_build")
      File.mkdir_p!(lib_dir)
      archive = Path.join(lib_dir, "libtflite_nif.a")
      File.write!(archive, "")
      frameworks = Path.join(ctx.tmp, "tflite/Frameworks")

      link =
        link_args(ctx, unquote(template), [
          "-Dtflite_static=true",
          "-Dtflite_dir=#{lib_dir}",
          "-Dtflite_framework_dir=#{frameworks}"
        ])

      assert archive in link

      for fw <- ["TensorFlowLiteC", "TensorFlowLiteCCoreML"] do
        assert Path.join(frameworks, "#{fw}.xcframework/#{unquote(slice)}") in link
        assert framework_linked?(link, fw)
      end

      assert framework_linked?(link, "CoreML")
      assert framework_linked?(link, "Metal")
    end

    test "#{template}: TFLite not enabled links no TFLite archive or framework", ctx do
      link = link_args(ctx, unquote(template), [])

      refute Enum.any?(link, &String.ends_with?(&1, "libtflite_nif.a"))
      refute Enum.any?(link, &String.contains?(&1, "TensorFlowLite"))
    end

    # Zig 0.17 caches the configure phase that globs mob/ios/*.swift. Without
    # b.dependOnDirectoryContents a Swift file added to mob after the first
    # build never reached swiftc until the zig cache was cleared.
    test "#{template}: a Swift file added to mob/ios reaches the next build's swiftc", ctx do
      ios_dir = Path.join(ctx.stubs.mob, "ios")
      File.write!(Path.join(ios_dir, "MobFirst.swift"), "")
      assert swift_compiled?(build_calls(ctx, unquote(template), [], "first"), "MobFirst.swift")

      File.write!(Path.join(ios_dir, "MobAdded.swift"), "")
      assert swift_compiled?(build_calls(ctx, unquote(template), [], "second"), "MobAdded.swift")
    end
  end

  defp framework_linked?(args, name) do
    args
    |> Enum.chunk_every(4, 1, :discard)
    |> Enum.any?(&(&1 == ["-Xlinker", "-framework", "-Xlinker", name]))
  end

  defp swift_compiled?(calls, name) do
    Enum.any?(calls, fn call ->
      "swiftc" in call and Enum.any?(call, &(Path.basename(&1) == name))
    end)
  end

  # Runs `zig build binary` against the generated iOS build file and returns the
  # argument list of the xcrun call that links the app binary (the one whose
  # `-o` is the module name).
  defp link_args(ctx, template, extra) do
    ctx
    |> build_calls(template, extra, "link")
    |> Enum.find(fn call ->
      call |> Enum.chunk_every(2, 1, :discard) |> Enum.any?(&match?(["-o", "TflApp" <> _], &1)) or
        Enum.any?(call, &String.ends_with?(&1, "/TflApp"))
    end)
    |> Kernel.||(flunk("no link call in the xcrun log"))
  end

  # Runs `zig build binary` (the zig cache is shared by every build of a
  # template in one test) and returns each xcrun call's arguments.
  defp build_calls(ctx, template, extra, run) do
    s = ctx.stubs
    ios = Path.join(ctx.project, "ios")
    # One file per xcrun call: zig runs them in parallel, and lines appended
    # to a shared log interleave.
    log = Path.join(ctx.tmp, "xcrun-#{template}-#{run}")
    File.mkdir_p!(log)

    # build_device.zig also compiles epmd and the errno shim.
    device_args =
      if template == "build_device.zig",
        do: ["-Dotp_release=0", "-Depmd_build_src=#{s.epmd}", "-Derrno_compat=#{s.errno_compat}"],
        else: []

    args =
      [
        "build",
        "--build-file",
        Path.join(ios, template),
        "binary",
        "-Dmob_dir=#{s.mob}",
        "-Dotp_root=#{s.otp}",
        "-Derts_vsn=erts-0",
        "-Dsdkroot=#{s.sdk}",
        "-Ddriver_tab=#{s.driver_tab}",
        "-Denif_keepalive=#{s.enif_keepalive}",
        "-Dproject_ios_dir=#{ios}",
        "-Dmodule_name=TflApp",
        "--cache-dir",
        Path.join(ctx.tmp, "zig-cache-#{template}"),
        "--prefix",
        Path.join(ctx.tmp, "zig-out-#{template}")
      ] ++ device_args ++ extra

    path = "#{s.bin}:#{System.get_env("PATH")}"

    {out, status} =
      System.cmd("zig", args,
        cd: ios,
        env: [{"XCRUN_LOG", log}, {"PATH", path}],
        stderr_to_stdout: true
      )

    assert status == 0, "zig build (#{template}) failed:\n#{out}"

    log
    |> Path.join("call.*")
    |> Path.wildcard()
    |> Enum.map(&(&1 |> File.read!() |> String.split("\n", trim: true)))
  end

  # Minimal stand-ins: tiny sources zig compiles for real, an empty OTP and SDK
  # tree (the link is faked), and an `xcrun` that logs each invocation's
  # arguments and touches every output it names.
  defp write_stubs(tmp) do
    root = Path.join(tmp, "stubs")
    mob = Path.join(root, "mob")
    otp = Path.join(root, "otp")
    sdk = Path.join(root, "sdk")
    bin = Path.join(root, "bin")
    src = Path.join(root, "src")

    for dir <- [Path.join(mob, "ios"), Path.join(otp, "erts-0/include"), sdk, bin, src] do
      File.mkdir_p!(dir)
    end

    driver_tab = Path.join(src, "driver_tab_ios.zig")
    File.write!(driver_tab, "export fn driver_tab_stub() void {}\n")
    enif_keepalive = Path.join(src, "enif_keepalive.c")
    File.write!(enif_keepalive, "int enif_keepalive_stub(void) { return 0; }\n")
    epmd = Path.join(src, "epmd")
    epmd_src = Path.join(epmd, "erts/epmd/src")
    File.mkdir_p!(epmd_src)

    for name <- ~w(epmd epmd_srv epmd_cli) do
      File.write!(Path.join(epmd_src, "#{name}.c"), "int #{name}_stub(void) { return 0; }\n")
    end

    # Compiled by (stand-in) xcrun, so only their presence matters.
    for name <- ~w(MobNode.m mob_nif.m mob_beam.m) do
      File.write!(Path.join(mob, "ios/#{name}"), "")
    end

    errno_compat = Path.join(src, "errno_compat.c")
    File.write!(errno_compat, "int errno_compat_stub(void) { return 0; }\n")

    xcrun = Path.join(bin, "xcrun")

    File.write!(xcrun, """
    #!/bin/sh
    # SDK queries (zig asks for the iOS SDK path to compile the C objects)
    # go to the real xcrun; everything else is recorded and faked.
    case " $* " in
      *" --show-sdk-path "*|*" --show-sdk-version "*) exec #{System.find_executable("xcrun")} "$@" ;;
    esac
    printf '%s\\n' "$@" > "$(mktemp "$XCRUN_LOG/call.XXXXXX")"
    prev=
    for a in "$@"; do
      case "$prev" in
        -o|-emit-objc-header-path) mkdir -p "$(dirname "$a")"; : > "$a" ;;
      esac
      prev=$a
    done
    """)

    File.chmod!(xcrun, 0o755)

    %{
      mob: mob,
      otp: otp,
      sdk: sdk,
      bin: bin,
      driver_tab: driver_tab,
      enif_keepalive: enif_keepalive,
      epmd: epmd,
      errno_compat: errno_compat
    }
  end
end
