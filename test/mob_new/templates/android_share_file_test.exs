# Template-assertion test: guards MobBridge.shareFile (reached by JNI name and
# descriptor from mob's mob_nif.zig) and MobBridge.handleFilesResult (MOB-525).
# credo:disable-for-this-file Jump.CredoChecks.VacuousTest
defmodule MobNew.Templates.AndroidShareFileTest do
  use ExUnit.Case, async: true

  alias MobNew.Templates.Lint

  @bridge Application.app_dir(
            :mob_new,
            "priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex"
          )

  setup_all do
    {:ok, bridge: File.read!(@bridge)}
  end

  test "shareFile exists on MobBridge with the exact JNI parameter order", %{bridge: src} do
    assert Lint.jvm_static_fun_owned_by_mob_bridge?(src, "shareFile")

    assert src =~
             ~r/@JvmStatic\s+fun shareFile\(pid: Long, path: String, mime: String, title: String\)/
  end

  test "shareFile uses FileProvider authority and grants read URI permission", %{bridge: src} do
    [_, body] = String.split(src, "fun shareFile(", parts: 2)
    [body | _] = String.split(body, "fun openUrl(", parts: 2)

    assert body =~ ~s("${activity.packageName}.fileprovider")
    assert body =~ "Intent.FLAG_GRANT_READ_URI_PERMISSION"
    assert body =~ "ClipData.newUri"
  end

  test "handleFilesResult uses createTempFile, DISPLAY_NAME, org.json, and deletes copies on failure",
       %{bridge: src} do
    [_, body] = String.split(src, "fun handleFilesResult(", parts: 2)
    [body | _] = String.split(body, "fun audio_start_recording(", parts: 2)

    assert body =~
             ~s|File.createTempFile("mob_file_", if (ext != null) ".$ext" else ".tmp", activity.cacheDir)|

    assert body =~ ~s|Regex("[A-Za-z0-9]{1,10}")|
    assert body =~ "OpenableColumns.DISPLAY_NAME"
    assert body =~ "org.json.JSONArray"
    assert body =~ "org.json.JSONObject"
    assert body =~ "copied.forEach { it.delete() }"
  end

  test "handleFilesResult delivers cancelled when activityRef is gone", %{bridge: src} do
    [_, body] = String.split(src, "fun handleFilesResult(", parts: 2)
    [body | _] = String.split(body, "Thread {", parts: 2)

    assert body =~
             ~r/activityRef\?\.get\(\) \?: run \{\s*nativeDeliverAtom2\(pid, "files", "cancelled"\)/
  end
end
