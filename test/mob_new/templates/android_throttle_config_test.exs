# Template-assertion test: guards the Android throttle-config wiring (MOB-134).
# credo:disable-for-this-file Jump.CredoChecks.VacuousTest
defmodule MobNew.Templates.AndroidThrottleConfigTest do
  use ExUnit.Case, async: true

  @bridge Path.expand(
            "../../../priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex",
            __DIR__
          )

  @jni Path.expand(
         "../../../priv/templates/mob.new/android/app/src/main/jni/beam_jni.c.eex",
         __DIR__
       )

  setup_all do
    {:ok, bridge: File.read!(@bridge), jni: File.read!(@jni)}
  end

  defp squish(s), do: s |> String.replace(~r/\s+/, " ") |> String.trim()
  defp has?(hay, needle), do: String.contains?(squish(hay), squish(needle))

  test "the config props are actually read", %{bridge: src} do
    # The whole bug: Mob.Renderer emitted these next to the handler they
    # configure and nothing on Android ever looked at them, so an app asking
    # for `throttle: 100, delta: 8` silently ran at the compiled-in default.
    assert has?(src, ~s|ApplyThrottleConfig(node.props, scrollH, "scroll_config")|)
    assert has?(src, ~s|ApplyThrottleConfig(node.props, dragHandle, "drag_config")|)
  end

  test "config is re-sent on every composition, not once", %{bridge: src} do
    # clear_taps zeroes throttle_ms/delta_threshold/last_emit_ns/seq at the top
    # of every frame because slots are reused, and each render re-registers the
    # handler under a new handle. A LaunchedEffect keyed on anything stable
    # would apply the config once and let every later frame run unconfigured.
    body = apply_fun(src)
    assert has?(body, "SideEffect {"), "config must be applied from a SideEffect"
    refute has?(body, "LaunchedEffect")
  end

  test "an absent leading/trailing flag means enabled, not off", %{bridge: src} do
    # Mob.Event.Throttle defaults both to true, so a missing key must not become
    # 0. Note what this does NOT claim: neither field has a native reader today
    # — mob_set_throttle_config stores them and throttleCheck never consults
    # them — so this pins the mapping for whoever implements them, not
    # behaviour in force now. An earlier version of this test justified itself
    # with "the native side reads 0 as off", which was simply untrue.
    body = apply_fun(src)
    assert has?(body, ~s|if (cfg.optBoolean("leading", true)) 1 else 0|)
    assert has?(body, ~s|if (cfg.optBoolean("trailing", true)) 1 else 0|)
  end

  test "every field is forwarded IN ORDER", %{bridge: src} do
    # Asserted as one call, not five independent substrings. throttleMs and
    # debounceMs are adjacent Ints with nothing to distinguish them to the
    # compiler, so swapping the two reverts MOB-134 completely — every app's
    # throttle becomes 0 — while five per-key assertions all still pass.
    assert has?(apply_fun(src), """
           MobBridge.nativeSetThrottleConfig(
             handle,
             cfg.optInt("throttle_ms", 0),
             cfg.optInt("debounce_ms", 0),
             cfg.optDouble("delta_threshold", 0.0),
           """)
  end

  test "the config is read straight off the JSONObject", %{bridge: src} do
    # Two things at once. Allocation: jsonObjectToMap would build a
    # LinkedHashMap plus five boxed values on the UI thread every composition,
    # i.e. every frame of an active scroll. Precision: routing delta_threshold
    # through Float turns 0.1 into 0.10000000149011612 on the way to a jdouble.
    # Comments stripped: the explanation above the call names both of the things
    # being refuted, and a test that fails on its own prose is worse than none.
    body = code_only(apply_fun(src))
    refute has?(body, "jsonObjectToMap")
    refute has?(body, "floatProp")
    assert has?(body, "cfg.optDouble(")
  end

  test "the nested-config cast matches what MobJson actually produces", %{bridge: src} do
    # `as? JSONObject` rests entirely on MobJson's compatibility contract, which
    # MobJson's own moduledoc names as the thing that silently breaks: nested
    # objects must stay org.json values, not plain Maps. If that ever changes,
    # this cast returns null, ApplyThrottleConfig early-returns, and Android
    # throttle config is dead again with no error anywhere.
    assert has?(src, "val cfg = props[configKey] as? JSONObject ?: return")

    json =
      File.read!(
        Path.expand(
          "../../../priv/templates/mob.new/android/app/src/main/java/MobJson.kt.eex",
          __DIR__
        )
      )

    assert json =~ "JSONObject",
           "MobJson must keep nested objects as org.json values for the cast above"
  end

  test "the config is skipped when there is no handle to attach it to", %{bridge: src} do
    # A config prop without its handler is meaningless. (Not because 0 is a
    # valid handle — mob_encode_event_handle requires generation >= 1, so the
    # smallest real handle is 4096 and both decoders reject <= 0. The guard is
    # about not calling at all for an unhandled node.)
    assert has?(apply_fun(src), "if (handle == null) return")
  end

  test "the Kotlin sender has a matching JNI stub reaching the native fn", %{
    bridge: src,
    jni: jni
  } do
    assert has?(src, "@JvmStatic external fun nativeSetThrottleConfig(")
    assert jni =~ "Java_<%= jni_package %>_MobBridge_nativeSetThrottleConfig"

    assert has?(jni, """
           mob_set_throttle_config((int)handle, (int)throttle_ms, (int)debounce_ms,
                                   (double)delta_threshold, (int)leading, (int)trailing);
           """)
  end

  # Body of ApplyThrottleConfig only. Bounded by the function's own closing
  # brace at column 0 — splitting on the next `private fun` overshoots, because
  # what follows is a `private data class`, and the body then swallows
  # MobScrollEvents (whose LaunchedEffect defeats the refute below).
  # Kotlin source with // comment lines removed.
  defp code_only(src) do
    src
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) |> String.starts_with?("//")))
    |> Enum.join("\n")
  end

  defp apply_fun(src) do
    src
    |> String.split("private fun ApplyThrottleConfig(")
    |> Enum.at(1)
    |> String.split("\n}\n", parts: 2)
    |> Enum.at(0)
  end
end
