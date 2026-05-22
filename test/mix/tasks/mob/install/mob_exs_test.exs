defmodule Mix.Tasks.Mob.Install.MobExsTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  describe "mob.install.mob_exs" do
    test "creates mob.exs" do
      test_project()
      |> Igniter.compose_task("mob.install.mob_exs")
      |> assert_creates("mob.exs")
    end

    test "mob.exs content has the expected structure" do
      igniter =
        test_project()
        |> Igniter.compose_task("mob.install.mob_exs")
        |> apply_igniter!()

      source = Rewrite.source!(igniter.rewrite, "mob.exs")
      content = Rewrite.Source.get(source, :content)

      assert content =~ "import Config"
      assert content =~ "config :mob_dev"
      assert content =~ "mob_dir:"
      assert content =~ "elixir_lib:"
    end

    test "patches .gitignore to ignore mob.exs" do
      igniter =
        test_project(files: %{".gitignore" => "/_build\n/deps\n"})
        |> Igniter.compose_task("mob.install.mob_exs")
        |> apply_igniter!()

      # Dotfiles are filtered out by the post-apply `**/*.*` include_glob
      # in `Igniter.Test.simulate_write/1`, so they only live in
      # `assigns[:test_files]` after apply. Read from there.
      content = igniter.assigns[:test_files][".gitignore"]
      assert content =~ "mob.exs"
    end

    test "is idempotent on .gitignore patches" do
      base =
        test_project(files: %{".gitignore" => "/_build\n/deps\n"})
        |> Igniter.compose_task("mob.install.mob_exs")
        |> apply_igniter!()

      first_content = base.assigns[:test_files][".gitignore"]

      after_second =
        base
        |> Igniter.compose_task("mob.install.mob_exs")
        |> apply_igniter!()

      assert after_second.assigns[:test_files][".gitignore"] == first_content
    end
  end
end
