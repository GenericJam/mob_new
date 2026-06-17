defmodule Mix.Tasks.Mob.Adopt.Native.IosTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  setup do
    cwd = File.cwd!()
    tmp = System.tmp_dir!() |> Path.join("mob_adopt_ios_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    File.cd!(tmp)
    on_exit(fn -> File.cd!(cwd) end)
    {:ok, tmp: tmp}
  end

  describe "mob.adopt.native.ios" do
    test "creates Info.plist and beam_main.m" do
      igniter =
        test_project()
        |> Igniter.compose_task("mob.adopt.native.ios")
        |> apply_igniter!()

      assert Rewrite.has_source?(igniter.rewrite, "ios/Info.plist")
      assert Rewrite.has_source?(igniter.rewrite, "ios/beam_main.m")
    end
  end
end
