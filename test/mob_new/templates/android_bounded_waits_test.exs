defmodule MobNew.Templates.AndroidBoundedWaitsTest do
  @moduledoc """
  Guards MOB-164: no unbounded wait on the UI thread from a NIF.

  Android runs the BEAM with `-S 1:1` — one normal scheduler. A NIF that
  blocks it is stalling every process on the device; a NIF that blocks it
  *without a bound* is a VM that never runs another process again if the main
  thread wedges. The distinction matters: a stall recovers, a hang does not.
  """
  use ExUnit.Case, async: true

  @bridge Path.expand(
            "../../../priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex",
            __DIR__
          )

  setup_all do
    {:ok, bridge: File.read!(@bridge)}
  end

  # Strip comments: this file explains the rejected shape in prose, so a plain
  # substring search would find `latch.await()` in the explanation.
  defp code_only(src) do
    src
    |> String.replace(~r|/\*.*?\*/|s, "")
    |> String.split("\n")
    |> Enum.map_join("\n", &Regex.replace(~r|^\s*//.*$|, &1, ""))
  end

  test "no latch is awaited without a timeout" do
    code = code_only(File.read!(@bridge))

    refute code =~ ~r/\.await\(\s*\)/,
           """
           An unbounded latch.await() is back.

           Every one of these runs on the single normal scheduler. If the main
           thread never answers — wedged, or gone during teardown — the wait
           never returns and no Erlang process on the device runs again.
           Timing out and returning the same value the no-activity path already
           returns costs nothing and cannot hang.
           """
  end

  test "every await names a TimeUnit, so the bound is explicit", %{bridge: src} do
    awaits =
      Regex.scan(~r/\.await\(([^)]*)\)/, code_only(src))
      |> Enum.map(fn [_, args] -> args end)

    assert awaits != [], "no awaits found — has the bridge been restructured?"

    for args <- awaits do
      assert args =~ "TimeUnit" or args =~ "timeoutMs",
             "await(#{args}) has no explicit unit; a bare number is ambiguous"
    end
  end

  test "the three formerly-unbounded readers are bounded", %{bridge: src} do
    # Named individually because these are the ones that were wrong, and a
    # regression in any of them is a device that stops responding entirely.
    for fun <- ~w(getSafeArea screenInfo clipboardGet) do
      body = function_body(src, fun)

      assert body =~ "latch.await(",
             "#{fun} no longer waits on a latch — if that is deliberate, drop it from this list"

      refute body =~ ~r/\.await\(\s*\)/, "#{fun} waits without a bound"
    end
  end

  defp function_body(src, name) do
    [_, rest] = String.split(src, "fun #{name}(", parts: 2)
    # Up to the next top-level @JvmStatic is comfortably past the end.
    rest |> String.split("@JvmStatic", parts: 2) |> hd()
  end
end
