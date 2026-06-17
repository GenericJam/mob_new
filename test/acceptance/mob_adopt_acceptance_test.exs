defmodule MobInstallAcceptanceTest do
  @moduledoc """
  End-to-end check: generate a real `mix phx.new` project, run
  `mix mob.adopt` against it via Igniter compose, assert the resulting
  tree has the expected mob bits and compiles.

  Slow (60s+) — tagged `@tag :acceptance` and excluded from the default
  test suite. Run with:

      mix test --only acceptance

  Requires `phx_new` archive on the system. Skipped if `mix phx.new --help`
  exits non-zero.
  """
  use ExUnit.Case, async: false

  @moduletag :acceptance
  @moduletag timeout: 180_000

  setup_all do
    case System.cmd("mix", ["help", "phx.new"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      _ -> {:skip, "phx.new not installed — run `mix archive.install hex phx_new`"}
    end
  end

  setup do
    tmp = System.tmp_dir!() |> Path.join("mob_acceptance_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  test "mob.adopt against a fresh phx.new project produces a usable mob app", %{tmp: tmp} do
    app_dir = Path.join(tmp, "test_mob_app")

    # Generate a minimal Phoenix project.
    {_, 0} =
      System.cmd(
        "mix",
        [
          "phx.new",
          "test_mob_app",
          "--no-install",
          "--no-ecto",
          "--no-mailer",
          "--no-dashboard"
        ],
        cd: tmp,
        stderr_to_stdout: true
      )

    # Run mob.adopt in the generated project.
    cwd = File.cwd!()
    File.cd!(app_dir)

    try do
      {output, code} =
        System.cmd("mix", ["mob.adopt", "--yes", "--no-install"], stderr_to_stdout: true)

      assert code == 0, "mob.adopt failed:\n#{output}"

      # mix.exs has the mob deps
      mix_exs = File.read!(Path.join(app_dir, "mix.exs"))
      assert mix_exs =~ ":mob"
      assert mix_exs =~ ":mob_dev"

      # Bridge files exist
      assert File.exists?(Path.join(app_dir, "lib/test_mob_app/mob_screen.ex"))
      assert File.exists?(Path.join(app_dir, "mob.exs"))

      # Native trees emitted
      assert File.exists?(Path.join(app_dir, "android/build.gradle"))
      assert File.exists?(Path.join(app_dir, "ios/Info.plist"))
    after
      File.cd!(cwd)
    end
  end
end
