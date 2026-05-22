defmodule Mix.Tasks.Mob.InstallTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Mob.Install

  describe "info/2" do
    test "composes the expected sub-tasks" do
      info = Install.info([], nil)

      assert info.composes == [
               "mob.install.deps",
               "mob.install.bridge",
               "mob.install.screen",
               "mob.install.mob_app",
               "mob.install.mob_exs",
               "mob.install.native",
               "mob.install.finalize"
             ]
    end

    test "defaults to both platforms on" do
      info = Install.info([], nil)
      assert info.defaults[:ios] == true
      assert info.defaults[:android] == true
    end
  end
end
