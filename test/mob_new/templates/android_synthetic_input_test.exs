# Template-assertion test: guards the generated Android synthetic-input bridge
# (MOB-160). The methods are reached from Zig by name and descriptor, so a
# rename or a signature change fails at runtime with a null JMethodID and a
# silent `{:error, :not_loaded}` — nothing at compile time notices.
# credo:disable-for-this-file Jump.CredoChecks.VacuousTest
defmodule MobNew.Templates.AndroidSyntheticInputTest do
  use ExUnit.Case, async: true

  @bridge Path.expand(
            "../../../priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex",
            __DIR__
          )

  setup_all do
    {:ok, bridge: File.read!(@bridge)}
  end

  defp squish(s), do: s |> String.replace(~r/\s+/, " ") |> String.trim()
  defp has?(haystack, needle), do: String.contains?(squish(haystack), squish(needle))

  # name => the JNI descriptor mob_nif.zig looks it up with. These must agree;
  # `cacheOptional` fails silently when they don't.
  @methods %{
    "tapXy" => "(FF)Z",
    "longPressXy" => "(FFJ)Z",
    "swipeXy" => "(FFFF)Z",
    "typeText" => "(Ljava/lang/String;)Z",
    "deleteBackward" => "()Z"
  }

  @descriptor_types %{
    "F" => "Float",
    "J" => "Long",
    "Ljava/lang/String;" => "String"
  }

  test "every synthetic-input method exists and is @JvmStatic", %{bridge: src} do
    for name <- Map.keys(@methods) do
      assert has?(src, "@JvmStatic fun #{name}("),
             "#{name} is missing or not @JvmStatic — JNI resolves it as a static method"
    end
  end

  test "each Kotlin signature matches the JNI descriptor it is cached with", %{bridge: src} do
    for {name, descriptor} <- @methods do
      [_, params] = Regex.run(~r/fun #{name}\(([^)]*)\)/, src)

      actual =
        params
        |> String.split(",", trim: true)
        |> Enum.map(fn param -> param |> String.split(":") |> List.last() |> String.trim() end)

      expected =
        descriptor
        |> String.replace(~r/^\(|\)Z$/, "")
        |> then(&Regex.scan(~r/Ljava\/lang\/String;|[FJIZ]/, &1))
        |> Enum.map(fn [token] -> Map.fetch!(@descriptor_types, token) end)

      assert actual == expected,
             """
             #{name} takes #{inspect(actual)} but mob_nif.zig caches it as
             #{descriptor}, i.e. #{inspect(expected)}.

             A mismatch is not a compile error. GetStaticMethodID returns null,
             the handle stays null, and every call returns {:error, :not_loaded}
             on a device with no other symptom.
             """
    end
  end

  test "clearText stays absent, on purpose", %{bridge: src} do
    refute has?(src, "fun clearText("),
           """
           clearText was re-added.

           Two implementations were tried on a physical device and both reported
           success while clearing nothing: dispatched backspaces coalesce within
           a frame (~4 of 200 registered), and Ctrl+A does not select in a
           Compose text field. Absent is the honest state — the JNI lookup is a
           cacheOptional, so capabilities/1 reports clear_text: false and calls
           return {:error, :not_loaded}.

           If you have a mechanism that actually works, delete this test and say
           so in decisions/.
           """

    assert has?(src, "`clearText` is deliberately NOT implemented"),
           "the comment explaining the omission is gone — it is the only thing " <>
             "stopping someone re-adding a broken clearText in good faith"
  end

  test "gestures dispatch over real time rather than synthesised timestamps", %{bridge: src} do
    # The bug this guards is invisible: every event still reaches the view and
    # every call still returns :ok, but no gesture is ever recognised.
    assert has?(src, "delay(50)"), "long press no longer holds for real time"
    assert has?(src, "delay(16)"), "swipe no longer spreads its moves over frames"

    assert has?(src, "private val gestureMutex"),
           "concurrent gestures would interleave their pointer streams"

    assert has?(src, "MotionEvent.ACTION_CANCEL"),
           "a gesture that fails between DOWN and UP must cancel the pointer, " <>
             "or every later touch is read as a second finger"
  end

  test "input results report what was consumed, not merely what was sent", %{bridge: src} do
    refute has?(src, "events.forEach { activity.dispatchKeyEvent(it) } true"),
           "typeText discards dispatch results and always returns true"

    assert has?(src, "if (activity.currentFocus == null)"),
           "typeText must check focus, or :no_first_responder is unreachable"
  end
end
