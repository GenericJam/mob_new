# Template-assertion test: guards the generated Android frame-timing bridge
# (MOB-146). The methods are reached from Zig by name and descriptor, and the
# JSON shape is parsed by Mob.RenderStats — none of that fails at compile time.
# credo:disable-for-this-file Jump.CredoChecks.VacuousTest
defmodule MobNew.Templates.AndroidFrameTimingTest do
  use ExUnit.Case, async: true

  @bridge Path.expand(
            "../../../priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex",
            __DIR__
          )

  setup_all do
    {:ok, bridge: File.read!(@bridge)}
  end

  defp squish(s), do: s |> String.replace(~r/\s+/, " ") |> String.trim()
  defp has?(haystack, needle), do: String.contains?(squish(code_only(haystack)), squish(needle))

  # Strip comments before matching. An earlier test in this repo passed by
  # matching a string that appeared only inside its own explanatory comment,
  # and this file discusses the rejected alternatives by name — so a plain
  # substring search would find `IdleHandler` in the prose that explains why it
  # is NOT used.
  defp code_only(src) do
    src
    |> String.replace(~r|/\*.*?\*/|s, "")
    |> String.split("\n")
    |> Enum.map_join("\n", &Regex.replace(~r|^\s*//.*$|, &1, ""))
  end

  test "both halves exist and are @JvmStatic", %{bridge: src} do
    # mob_nif.zig caches these as "()Ljava/lang/String;" and "(Z)Z".
    assert has?(src, "@JvmStatic fun renderStats(): String")
    assert has?(src, "@JvmStatic fun renderStatsEnable(on: Boolean): Boolean")
  end

  test "emits the key names Mob.RenderStats parses", %{bridge: src} do
    # native_summary/1 reads these by name. A rename here does not fail to
    # compile and does not fail to run — it produces a summary of zero samples,
    # which is indistinguishable from "the feature is off".
    for key <- ~w(enabled recorded dropped samples apply_us transition seq) do
      assert has?(src, ~s|\\"#{key}\\"|), "renderStats no longer emits #{key}"
    end
  end

  test "measurement rides the frame, registered without an intervening post", %{bridge: src} do
    # Two distinct bugs are guarded here, and both produce a plausible number
    # rather than an error.
    #
    # The frame callback is the closing bracket: a message posted from inside
    # it cannot run until the traversal finishes, because the traversal is
    # synchronous on that thread.
    assert has?(src, "choreographer.postFrameCallback"),
           "the closing bracket must be inside a frame callback"

    assert has?(src, "mainHandler.post {"),
           "without a post from inside the callback the bracket closes before layout"

    # And it must be registered straight from the calling thread.
    # ViewRootImpl.scheduleTraversals installs a sync barrier that holds
    # non-async messages until doTraversal runs, so registering from inside a
    # posted Runnable lands on the frame AFTER the one Compose recomposes in,
    # and the sample absorbs an extra frame — biased upward exactly when the
    # screen is busy, which is when these measurements are taken.
    refute has?(src, "mainHandler.post { choreographer"),
           "the frame callback must not be registered from inside a posted Runnable"
  end

  test "the clock does not count deep sleep", %{bridge: src} do
    # elapsedRealtimeNanos advances while the device sleeps, so a run spanning
    # a screen-off produces a sample of minutes. iOS's CACurrentMediaTime does
    # not count sleep either.
    assert has?(src, "System.nanoTime() - startNanos"),
           "frame timing must use a clock that stops when the device does"
  end

  test "enabling clears, disabling does not", %{bridge: src} do
    # native_disable/0 documents that recorded samples stay readable, and the
    # natural shape is enable, drive, disable, read. Clearing on disable makes
    # that read return an empty window, which looks like "the feature is off".
    assert has?(src, "if (on) { synchronized(renderStatLock) {"),
           "the buffer must be cleared only when enabling"
  end

  test "the disabled path stays cheap", %{bridge: src} do
    # Read on every setRootJson. If this stops being a plain volatile field
    # read, every app pays for instrumentation it never enables.
    assert has?(src, "@Volatile private var renderStatsOn = false"),
           "the enabled flag must be a volatile read, not a lock"

    assert has?(src, "val measuring = renderStatsOn"),
           "setRootJson must read the flag once and branch on it"
  end

  test "the transition string is escaped into the JSON", %{bridge: src} do
    # transition reaches this from nif_set_transition, which accepts any atom
    # up to 15 chars verbatim. One containing a quote makes the payload
    # unparseable and costs the reader the whole window, not the one sample.
    assert has?(src, "append(jsonEscape(sample.transition))"),
           "an unescaped transition can invalidate the entire payload"
  end
end
