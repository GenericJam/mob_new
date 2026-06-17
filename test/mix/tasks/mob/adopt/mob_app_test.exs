defmodule Mix.Tasks.Mob.Adopt.MobAppTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  describe "mob.adopt.mob_app (default — LiveView flavour)" do
    test "generates LV-flavoured mob_app.ex that boots the host Phoenix app" do
      igniter =
        test_project()
        |> Igniter.compose_task("mob.adopt.mob_app")
        |> apply_igniter!()

      content =
        Rewrite.source!(igniter.rewrite, "lib/test/mob_app.ex")
        |> Rewrite.Source.get(:content)

      assert content =~ "defmodule Test.MobApp"
      assert content =~ "{:ok, _} = Application.ensure_all_started(:test)"
      assert content =~ "Mob.NativeLogger.install()"
      assert content =~ "Ecto.Migrator.run"
    end

    test "writes src/<app>.erl bootstrap" do
      igniter =
        test_project()
        |> Igniter.compose_task("mob.adopt.mob_app")
        |> apply_igniter!()

      erl = Rewrite.source!(igniter.rewrite, "src/test.erl") |> Rewrite.Source.get(:content)
      assert erl =~ "test"
    end

    test "patches mix.exs with erlc_paths and erlc_options" do
      igniter =
        test_project()
        |> Igniter.compose_task("mob.adopt.mob_app")
        |> apply_igniter!()

      content = Rewrite.source!(igniter.rewrite, "mix.exs") |> Rewrite.Source.get(:content)
      assert content =~ ~s(erlc_paths: ["src"])
      assert content =~ "erlc_options: [:debug_info]"
    end
  end

  describe "mob.adopt.mob_app --no-live-view (thin-client flavour)" do
    test "generates thin mob_app.ex using `use Mob.App` without ensure_all_started" do
      igniter =
        test_project()
        |> Igniter.compose_task("mob.adopt.mob_app", ["--no-live-view"])
        |> apply_igniter!()

      content =
        Rewrite.source!(igniter.rewrite, "lib/test/mob_app.ex")
        |> Rewrite.Source.get(:content)

      assert content =~ "defmodule Test.MobApp"
      assert content =~ "use Mob.App"
      assert content =~ "def navigation"
      assert content =~ "def on_start"
      assert content =~ "Mob.Screen.start_root(Test.MobScreen)"
      assert content =~ "Mob.DNS.configure_pure_beam"

      # Crucially, the thin variant does NOT actually boot the host
      # Phoenix app or run Ecto migrations on-device. (The docstring
      # mentions both in prose, but the code body does not.)
      refute content =~ "{:ok, _} = Application.ensure_all_started"
      refute content =~ "Ecto.Migrator.run"
    end
  end
end
