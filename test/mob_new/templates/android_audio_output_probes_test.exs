defmodule MobNew.Templates.AndroidAudioOutputProbesTest do
  use ExUnit.Case, async: true

  @android Path.expand("../../../priv/templates/mob.new/android/app/src/main", __DIR__)
  @bridge Path.join(@android, "java/MobBridge.kt.eex")

  # The audio output probes (Mob.Audio.output_status/0, output_level/1) call
  # app-owned MobBridge methods over JNI. The native side caches them with
  # cacheOptional + null-guard, so a drifted bridge that lacks them no-ops
  # rather than failing nif_load — but a freshly generated app must ship them
  # for the probes to actually work. This pins their presence in the template.
  test "host MobBridge.kt template scaffolds the audio output probe methods" do
    src = File.read!(@bridge)

    assert src =~ "fun audioOutputStatus(): FloatArray",
           "MobBridge.kt.eex must scaffold audioOutputStatus() for Mob.Audio.output_status/0"

    assert src =~ "fun audioOutputLevel(source: String): FloatArray",
           "MobBridge.kt.eex must scaffold audioOutputLevel(source) for Mob.Audio.output_level/1"

    # The level probe meters Mob.Audio's OWN player session (an own-session tap
    # works with RECORD_AUDIO). It must NOT attach to session 0 — the global
    # output mix is privileged on modern Android (ERROR_NO_INIT for a normal
    # app); global capture lives in a separate MediaProjection plugin.
    assert src =~ "audioPlayer?.audioSessionId",
           "audioOutputLevel(:mob) must meter the app's own player session"

    refute src =~ "Visualizer(0)",
           "audioOutputLevel must not tap session 0 — privileged on modern Android"

    assert src =~ "MEASUREMENT_MODE_PEAK_RMS",
           "audioOutputLevel must use peak/rms measurement mode"
  end
end
