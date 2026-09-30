defmodule Mix.Tasks.Mob.NewTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Mob.New

  @switches [
    no_install: :boolean,
    ios: :boolean,
    android: :boolean,
    dest: :string,
    local: :boolean,
    liveview: :boolean,
    python: :boolean
  ]

  defp platforms(argv) do
    {opts, _args, _} = OptionParser.parse(argv, strict: @switches)
    New.resolve_platforms(opts)
  end

  describe "resolve_platforms/1 (CLI flag → {no_ios?, no_android?})" do
    test "default: both platforms kept" do
      assert platforms(["my_app"]) == {:ok, {false, false}}
    end

    test "--no-android skips android, keeps ios" do
      assert platforms(["my_app", "--no-android"]) == {:ok, {false, true}}
    end

    test "--no-ios skips ios, keeps android" do
      assert platforms(["my_app", "--no-ios"]) == {:ok, {true, false}}
    end

    test "--ios is iOS-only (skips android)" do
      assert platforms(["my_app", "--ios"]) == {:ok, {false, true}}
    end

    test "--android is Android-only (skips ios)" do
      assert platforms(["my_app", "--android"]) == {:ok, {true, false}}
    end

    test "excluding both platforms is an error" do
      assert {:error, msg} = platforms(["my_app", "--no-ios", "--no-android"])
      assert msg =~ "Cannot exclude both platforms"
    end

    test "--ios with --no-android (both name android-skip) is consistent, not an error" do
      assert platforms(["my_app", "--ios", "--no-android"]) == {:ok, {false, true}}
    end
  end

  describe "run/1 flag validation" do
    @tag :tmp_dir
    test "--deliver with --liveview is rejected before anything is generated",
         %{tmp_dir: tmp} do
      assert_raise Mix.Error, ~r/--deliver .* cannot be combined with --liveview/, fn ->
        New.run(["my_app", "--liveview", "--deliver", "--no-install", "--dest", tmp])
      end

      refute File.exists?(Path.join(tmp, "my_app"))
    end
  end
end
