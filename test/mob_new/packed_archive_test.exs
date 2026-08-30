defmodule MobNew.PackedArchiveTest do
  use ExUnit.Case, async: false

  @tag :integration
  test "packed Hex source builds an installable archive that pins native and LiveView projects" do
    source_root = Path.expand("../..", __DIR__)
    tmp = Path.join(System.tmp_dir!(), "mob_new_packed_#{System.unique_integer([:positive])}")
    package_dir = Path.join(tmp, "package")
    archive = Path.join(tmp, "mob_new.ez")
    mix_home = Path.join(tmp, "mix_home")
    generated = Path.join(tmp, "generated")

    File.mkdir_p!(mix_home)
    File.mkdir_p!(generated)

    on_exit(fn -> File.rm_rf!(tmp) end)

    run_mix!(source_root, ["hex.build", "--unpack", "--output", package_dir])

    package_env = [MIX_ENV: "prod"]

    run_mix!(package_dir, ["deps.get"], package_env)

    run_mix!(package_dir, ["archive.build", "--output", archive], package_env)

    copy_phx_new_archive!(mix_home)
    run_mix!(tmp, ["archive.install", archive, "--force"], MIX_HOME: mix_home)

    run_mix!(tmp, ["mob.new", "packed_native", "--no-install", "--dest", generated],
      MIX_HOME: mix_home
    )

    run_mix!(
      tmp,
      ["mob.new", "packed_liveview", "--liveview", "--no-install", "--dest", generated],
      MIX_HOME: mix_home
    )

    assert_zig_pin!(Path.join([generated, "packed_native", ".tool-versions"]))
    assert_zig_pin!(Path.join([generated, "packed_liveview", ".tool-versions"]))
  end

  defp run_mix!(working_dir, args, env \\ []) do
    {output, status} =
      System.cmd(System.find_executable("mix"), args,
        cd: working_dir,
        env: Enum.map(env, fn {key, value} -> {to_string(key), value} end),
        stderr_to_stdout: true
      )

    assert status == 0, "mix #{Enum.join(args, " ")} failed:\n#{output}"
    output
  end

  defp copy_phx_new_archive!(mix_home) do
    source =
      Mix.path_for(:archives)
      |> Path.join("phx_new-*")
      |> Path.wildcard()
      |> List.first()

    assert source, "phx_new archive must be installed to exercise packed LiveView generation"

    destination = Path.join([mix_home, "archives", Path.basename(source)])
    File.mkdir_p!(Path.dirname(destination))
    File.cp_r!(source, destination)
  end

  defp assert_zig_pin!(path) do
    assert File.read!(path) =~ "zig #{required_zig_version()}"
  end

  defp required_zig_version do
    Path.expand("../../.tool-versions", __DIR__)
    |> File.read!()
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case String.split(line) do
        ["zig", version] -> version
        _ -> nil
      end
    end)
  end
end
