defmodule MobNew.Templates.AndroidCameraFrameStreamStrippedTest do
  use ExUnit.Case, async: true

  @android Path.expand("../../../priv/templates/mob.new/android/app/src/main", __DIR__)
  @bridge Path.join(@android, "java/MobBridge.kt.eex")
  @main_activity Path.join(@android, "java/MainActivity.kt.eex")
  @beam_jni Path.join(@android, "jni/beam_jni.c.eex")

  # Drift guard. The live-camera frame stream moved to the mob_camera plugin. The
  # host template must not keep the Kotlin `nativeDeliverCameraFrame` extern or its
  # C thunk: the thunk calls the (now plugin-owned) `mob_deliver_camera_frame`,
  # whose absence on a stripped core makes the whole .so fail to dlopen at
  # MainActivity.<clinit>, crashing every generated app on launch. (The broader
  # "every Kotlin extern has a matching C thunk" invariant is covered by
  # project_generator_test.exs:509; this pins the specific camera frame-stream
  # removal + that preview stays.)
  test "host beam_jni.c template has no camera frame deliver thunk" do
    src = File.read!(@beam_jni)

    refute src =~ "mob_deliver_camera_frame",
           "beam_jni.c.eex must not call mob_deliver_camera_frame (moved to mob_camera) " <>
             "— a dangling C symbol breaks dlopen and crashes boot."

    refute src =~ "nativeDeliverCameraFrame",
           "beam_jni.c.eex must not define the camera frame deliver thunk."
  end

  test "host MobBridge.kt template drops the camera frame stream but keeps preview" do
    src = File.read!(@bridge)

    for gone <- ~w(nativeDeliverCameraFrame frameStreamActive deliverFrame
                   camera_start_frame_stream ImageAnalysis) do
      refute src =~ gone,
             "MobBridge.kt.eex must not reference `#{gone}` — the live frame stream " <>
               "moved to the mob_camera plugin."
    end

    # Preview stays in the host (descope: camera_preview component remains in core
    # until a plugin Compose native-view capability exists).
    assert src =~ "MobCameraPreview", "the camera preview composable must stay"

    assert src =~ ~s("camera_preview" -> MobCameraPreview),
           "the camera_preview render case must stay"
  end

  # The host camera CAPTURE path is dead once core's camera NIF is stripped (the
  # mob_camera plugin owns capture via its own bridge). It must not linger in the
  # host template's MobBridge.kt (capture methods) or MainActivity.kt (launchers).
  test "host templates drop the dead camera capture path" do
    bridge = File.read!(@bridge)
    main = File.read!(@main_activity)

    for gone <- ~w(camera_capture_photo camera_capture_video handleCameraPhotoResult
                   handleCameraVideoResult pendingCameraPid) do
      refute bridge =~ gone, "MobBridge.kt.eex must not keep dead capture method `#{gone}`"
    end

    for gone <- ~w(launchCameraPhoto launchCameraVideo cameraPhotoLauncher cameraVideoLauncher) do
      refute main =~ gone, "MainActivity.kt.eex must not keep dead camera launcher `#{gone}`"
    end
  end
end
