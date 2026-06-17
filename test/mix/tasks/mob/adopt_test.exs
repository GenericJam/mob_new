defmodule Mix.Tasks.Mob.AdoptTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Mob.Adopt

  describe "info/2" do
    test "composes the expected sub-tasks" do
      info = Adopt.info([], nil)

      assert info.composes == [
               "mob.adopt.deps",
               "mob.adopt.bridge",
               "mob.adopt.screen",
               "mob.adopt.mob_app",
               "mob.adopt.mob_exs",
               "mob.adopt.native",
               "mob.adopt.finalize"
             ]
    end

    test "defaults to both platforms on" do
      info = Adopt.info([], nil)
      assert info.defaults[:ios] == true
      assert info.defaults[:android] == true
    end
  end
end
