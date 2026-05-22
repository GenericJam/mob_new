defmodule Mix.Tasks.Mob.Install.DepsTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  describe "mob.install.deps" do
    test "adds :mob and :mob_dev to mix.exs" do
      igniter =
        test_project()
        |> Igniter.compose_task("mob.install.deps")
        |> apply_igniter!()

      source = Rewrite.source!(igniter.rewrite, "mix.exs")
      content = Rewrite.Source.get(source, :content)

      assert content =~ ":mob"
      assert content =~ ":mob_dev"
      assert content =~ "only: :dev"
    end

    test "is idempotent on a second run" do
      igniter =
        test_project()
        |> Igniter.compose_task("mob.install.deps")
        |> apply_igniter!()
        |> Igniter.compose_task("mob.install.deps")

      assert_unchanged(igniter)
    end
  end
end
