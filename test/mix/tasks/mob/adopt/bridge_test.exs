defmodule Mix.Tasks.Mob.Adopt.BridgeTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  describe "mob.adopt.bridge" do
    test "injects MobHook into assets/js/app.js when present" do
      app_js = """
      import {Socket} from "phoenix"
      let liveSocket = new LiveSocket("/live", Socket, {hooks: {}})
      """

      igniter =
        test_project(files: %{"assets/js/app.js" => app_js})
        |> Igniter.compose_task("mob.adopt.bridge")
        |> apply_igniter!()

      source = Rewrite.source!(igniter.rewrite, "assets/js/app.js")
      content = Rewrite.Source.get(source, :content)
      assert content =~ "MobHook"
    end

    test "injects bridge element into root.html.heex when present" do
      root_heex = """
      <html>
        <body>
          Hello
        </body>
      </html>
      """

      igniter =
        test_project(files: %{"lib/test_web/components/layouts/root.html.heex" => root_heex})
        |> Igniter.compose_task("mob.adopt.bridge")
        |> apply_igniter!()

      source = Rewrite.source!(igniter.rewrite, "lib/test_web/components/layouts/root.html.heex")
      content = Rewrite.Source.get(source, :content)
      assert content =~ ~s(id="mob-bridge")
    end

    test "warns when no app.js exists" do
      igniter =
        test_project()
        |> Igniter.compose_task("mob.adopt.bridge")

      assert Enum.any?(igniter.warnings, &String.contains?(&1, "MobHook"))
    end

    test "--no-live-view skips all patches with a notice" do
      app_js = """
      import {Socket} from "phoenix"
      let liveSocket = new LiveSocket("/live", Socket, {hooks: {}})
      """

      root_heex = """
      <html><body>Hello</body></html>
      """

      # `apply_igniter!` resets `notices` to [] during `simulate_write`,
      # so we inspect the un-applied igniter directly to assert on
      # notices, then materialise separately to check file content.
      igniter =
        test_project(
          files: %{
            "assets/js/app.js" => app_js,
            "lib/test_web/components/layouts/root.html.heex" => root_heex
          }
        )
        |> Igniter.compose_task("mob.adopt.bridge", ["--no-live-view"])

      # Notice emitted.
      assert Enum.any?(igniter.notices, &String.contains?(&1, "skipped (--no-live-view)"))

      # And there should be NO file changes queued for the bridge files.
      app_js_source = Rewrite.source!(igniter.rewrite, "assets/js/app.js")
      refute Rewrite.Source.get(app_js_source, :content) =~ "MobHook"

      heex_source =
        Rewrite.source!(igniter.rewrite, "lib/test_web/components/layouts/root.html.heex")

      refute Rewrite.Source.get(heex_source, :content) =~ "mob-bridge"
    end
  end
end
