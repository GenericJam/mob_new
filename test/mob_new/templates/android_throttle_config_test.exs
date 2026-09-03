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
    # The native side reads 0 as "off" rather than "unset", while
    # Mob.Event.Throttle defaults both to true. Mapping a missing key to 0
    # would silently disable edges the app never asked to disable.
    body = apply_fun(src)
    assert has?(body, ~s|if (boolProp(m, "leading") == false) 0 else 1|)
    assert has?(body, ~s|if (boolProp(m, "trailing") == false) 0 else 1|)
  end

  test "every field the renderer encodes is forwarded", %{bridge: src} do
    # encode_throttle/1 emits exactly these five. Dropping one leaves it at the
    # native default with no error anywhere.
    body = apply_fun(src)

    for key <- ~w(throttle_ms debounce_ms delta_threshold leading trailing) do
      assert has?(body, ~s|"#{key}"|), "#{key} is never forwarded"
    end
  end

  test "the config is skipped when there is no handle to attach it to", %{bridge: src} do
    # A config prop without its handler is meaningless, and handle 0 is a real
    # slot — passing it would configure an unrelated node's throttle.
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
  defp apply_fun(src) do
    src
    |> String.split("private fun ApplyThrottleConfig(")
    |> Enum.at(1)
    |> String.split("\n}\n", parts: 2)
    |> Enum.at(0)
  end
end
