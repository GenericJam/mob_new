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

    assert src =~ "fun audioOutputLevel(source: String): FloatArray?",
           "MobBridge.kt.eex must scaffold audioOutputLevel(source) for Mob.Audio.output_level/1"

    # The level probe reads the global output mix (session 0) so it observes
    # audio from native players that bypass Mob.Audio (e.g. a game's AudioTrack).
    assert src =~ "Visualizer(0)",
           "audioOutputLevel must tap the global output mix (session 0)"

    # JNI return signatures the native cache expects: both return float[] (`[F`).
    assert src =~ "MEASUREMENT_MODE_PEAK_RMS",
           "audioOutputLevel must use peak/rms measurement mode"
  end
end
