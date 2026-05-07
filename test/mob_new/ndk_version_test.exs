defmodule MobNew.NdkVersionTest do
  use ExUnit.Case, async: true
  alias MobNew.NdkVersion

  test "recommended/0 returns major.minor.patch string" do
    v = NdkVersion.recommended()
    assert is_binary(v)
    assert v =~ ~r/^\d+\.\d+\.\d+$/, "expected major.minor.patch, got #{inspect(v)}"
  end

  describe "drift against mob_dev" do
    @mob_dev_source Path.expand("../../../mob_dev/lib/mob_dev/ndk_version.ex", __DIR__)

    test "MobNew.NdkVersion.recommended/0 matches MobDev.NdkVersion.@recommended" do
      cond do
        not File.regular?(@mob_dev_source) ->
          # Sibling repo not present (e.g. CI checked out only mob_new, or
          # we're running from inside an extracted Hex package). Skip — this
          # check is only meaningful when both repos are co-located.
          IO.puts("[skip] mob_dev source not at #{@mob_dev_source}")

        true ->
          contents = File.read!(@mob_dev_source)

          mob_dev_recommended =
            case Regex.run(~r/@recommended\s+"([^"]+)"/, contents, capture: :all_but_first) do
              [v] -> v
              _ -> flunk("could not extract @recommended from #{@mob_dev_source}")
            end

          assert NdkVersion.recommended() == mob_dev_recommended,
                 """
                 NDK version drift between mob_new and mob_dev.
                   MobNew.NdkVersion.recommended/0 = #{inspect(NdkVersion.recommended())}
                   MobDev.NdkVersion.@recommended  = #{inspect(mob_dev_recommended)}

                 When you bump @recommended in mob_dev/lib/mob_dev/ndk_version.ex, also bump
                 it in mob_new/lib/mob_new/ndk_version.ex. They feed the same generated
                 Android project — drift here means the generated build.gradle pins a
                 different NDK than the cross-compile that built libbeam.a.
                 """
      end
    end
  end

  test "ndk_version threads through ProjectGenerator.assigns/2" do
    a = MobNew.ProjectGenerator.assigns("foo")
    assert a.ndk_version == NdkVersion.recommended()
  end
end
