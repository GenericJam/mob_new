defmodule Mix.Tasks.Mob.Adopt.ScreenTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  describe "mob.adopt.screen" do
    test "creates lib/<app>/mob_screen.ex reading host URL from app config" do
      igniter =
        test_project()
        |> Igniter.compose_task("mob.adopt.screen")
        |> apply_igniter!()

      source = Rewrite.source!(igniter.rewrite, "lib/test/mob_screen.ex")
      content = Rewrite.Source.get(source, :content)

      assert content =~ "Test.MobScreen"
      assert content =~ "Application.get_env(:mob, :host_url"
      assert content =~ ~s("http://127.0.0.1:4000/")
      refute content =~ "Mob.LiveView.local_url"
    end

    test "is idempotent" do
      igniter =
        test_project()
        |> Igniter.compose_task("mob.adopt.screen")
        |> apply_igniter!()
        |> Igniter.compose_task("mob.adopt.screen")

      assert_unchanged(igniter)
    end

    test "--host-url writes `config :mob, host_url: URL` to config/config.exs" do
      igniter =
        test_project()
        |> Igniter.compose_task("mob.adopt.screen", ["--host-url", "https://my.fly.dev/"])
        |> apply_igniter!()

      # The mob_screen.ex itself remains URL-agnostic — it reads the config.
      mob_screen = Rewrite.source!(igniter.rewrite, "lib/test/mob_screen.ex")
      refute Rewrite.Source.get(mob_screen, :content) =~ "https://my.fly.dev/"

      # config/config.exs gets the new key.
      config = Rewrite.source!(igniter.rewrite, "config/config.exs")
      content = Rewrite.Source.get(config, :content)
      assert content =~ "config :mob"
      assert content =~ ~s(host_url: "https://my.fly.dev/")
    end
  end
end
