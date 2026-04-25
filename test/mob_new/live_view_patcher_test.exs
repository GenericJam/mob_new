defmodule MobNew.LiveViewPatcherTest do
  use ExUnit.Case, async: true

  alias MobNew.LiveViewPatcher

  # ── inject_mob_hook/1 ─────────────────────────────────────────────────────────

  describe "inject_mob_hook/1" do
    @sample_app_js """
    import "phoenix_html"
    import {Socket} from "phoenix"
    import {LiveSocket} from "phoenix_live_view"
    import topbar from "../vendor/topbar"

    let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
    let liveSocket = new LiveSocket("/live", Socket, {
      longPollFallbackMs: 2500,
      params: {_csrf_token: csrfToken}
    })

    liveSocket.connect()
    window.liveSocket = liveSocket
    """

    test "injects MobHook definition after last import" do
      result = LiveViewPatcher.inject_mob_hook(@sample_app_js)
      assert result =~ "const MobHook ="
      # MobHook should appear after the import block
      import_pos = :binary.match(result, "import topbar") |> elem(0)
      hook_pos = :binary.match(result, "const MobHook") |> elem(0)
      assert hook_pos > import_pos
    end

    test "registers MobHook in LiveSocket hooks option" do
      result = LiveViewPatcher.inject_mob_hook(@sample_app_js)
      assert result =~ "hooks: {MobHook}"
    end

    test "is idempotent — does not double-inject if MobHook already present" do
      once = LiveViewPatcher.inject_mob_hook(@sample_app_js)
      twice = LiveViewPatcher.inject_mob_hook(once)
      assert once == twice
    end

    test "injects pushEvent-based send function" do
      result = LiveViewPatcher.inject_mob_hook(@sample_app_js)
      assert result =~ "pushEvent(\"mob_message\", data)"
    end

    test "injects handleEvent-based onMessage function" do
      result = LiveViewPatcher.inject_mob_hook(@sample_app_js)
      assert result =~ "handleEvent(\"mob_push\", handler)"
    end

    test "handles LiveSocket with existing hooks: {} key" do
      content = """
      import {LiveSocket} from "phoenix_live_view"
      let liveSocket = new LiveSocket("/live", Socket, {hooks: {}})
      liveSocket.connect()
      """

      result = LiveViewPatcher.inject_mob_hook(content)
      assert result =~ "hooks: {MobHook}"
      refute result =~ "hooks: {}"
    end

    test "handles LiveSocket with existing hooks containing other hooks" do
      content = """
      import {LiveSocket} from "phoenix_live_view"
      let liveSocket = new LiveSocket("/live", Socket, {hooks: {OtherHook}})
      liveSocket.connect()
      """

      result = LiveViewPatcher.inject_mob_hook(content)
      assert result =~ "MobHook"
      assert result =~ "OtherHook"
    end
  end

  # ── inject_mob_bridge_element/1 ───────────────────────────────────────────────

  describe "inject_mob_bridge_element/1" do
    @sample_root_html """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
      </head>
      <body class="bg-white">
        {@inner_content}
      </body>
    </html>
    """

    test "injects mob-bridge div after opening body tag" do
      result = LiveViewPatcher.inject_mob_bridge_element(@sample_root_html)
      assert result =~ ~s(id="mob-bridge")
      assert result =~ ~s(phx-hook="MobHook")
    end

    test "bridge element appears before inner_content" do
      result = LiveViewPatcher.inject_mob_bridge_element(@sample_root_html)
      bridge_pos = :binary.match(result, "mob-bridge") |> elem(0)
      inner_pos = :binary.match(result, "inner_content") |> elem(0)
      assert bridge_pos < inner_pos
    end

    test "is idempotent — does not double-inject" do
      once = LiveViewPatcher.inject_mob_bridge_element(@sample_root_html)
      twice = LiveViewPatcher.inject_mob_bridge_element(once)
      assert once == twice
      # Only one mob-bridge element
      count = length(:binary.matches(twice, "mob-bridge"))
      assert count == 1
    end

    test "preserves body tag attributes" do
      result = LiveViewPatcher.inject_mob_bridge_element(@sample_root_html)
      assert result =~ ~s(<body class="bg-white">)
    end
  end

  # ── inject_deps/3 ─────────────────────────────────────────────────────────────

  describe "inject_deps/3" do
    @sample_mix_exs """
    defmodule MyApp.MixProject do
      use Mix.Project

      defp deps do
        [
          {:phoenix, "~> 1.7"},
          {:ecto, "~> 3.0"}
        ]
      end
    end
    """

    test "injects mob dep into deps function" do
      result = LiveViewPatcher.inject_deps(@sample_mix_exs, ~s({:mob, "~> 0.2"}), ~s({:mob_dev, "~> 0.2", only: :dev}))
      assert result =~ ~s({:mob, "~> 0.2"})
    end

    test "injects mob_dev dep into deps function" do
      result = LiveViewPatcher.inject_deps(@sample_mix_exs, ~s({:mob, "~> 0.2"}), ~s({:mob_dev, "~> 0.2", only: :dev}))
      assert result =~ ~s({:mob_dev, "~> 0.2", only: :dev})
    end

    test "preserves existing deps" do
      result = LiveViewPatcher.inject_deps(@sample_mix_exs, ~s({:mob, "~> 0.2"}), ~s({:mob_dev, "~> 0.2", only: :dev}))
      assert result =~ ~s({:phoenix, "~> 1.7"})
      assert result =~ ~s({:ecto, "~> 3.0"})
    end

    test "is idempotent — does not double-inject if :mob already present" do
      once = LiveViewPatcher.inject_deps(@sample_mix_exs, ~s({:mob, "~> 0.2"}), ~s({:mob_dev, "~> 0.2", only: :dev}))
      twice = LiveViewPatcher.inject_deps(once, ~s({:mob, "~> 0.2"}), ~s({:mob_dev, "~> 0.2", only: :dev}))
      assert once == twice
    end
  end

  # ── mob_live_app_content/4 ────────────────────────────────────────────────────

  describe "mob_live_app_content/4" do
    @secret "testSecretKeyBase1234567890abcdefghijklmnopqrstuvwxyz"
    @salt   "testSalt"

    defp live_app_content, do: LiveViewPatcher.mob_live_app_content("MyApp", "my_app", @secret, @salt)

    test "contains correct module name" do
      assert live_app_content() =~ "defmodule MyApp.MobApp"
    end

    test "calls Application.ensure_all_started with app name" do
      assert live_app_content() =~ "ensure_all_started(:my_app)"
    end

    test "calls Mob.Screen.start_root with MobScreen" do
      assert live_app_content() =~ "Mob.Screen.start_root(MyApp.MobScreen)"
    end

    test "installs Mob.NativeLogger" do
      assert live_app_content() =~ "Mob.NativeLogger.install()"
    end

    test "starts Erlang distribution" do
      assert live_app_content() =~ "Mob.Dist.ensure_started"
    end

    test "sets Application.put_env for :mob liveview_port" do
      assert live_app_content() =~ "Application.put_env(:mob, :liveview_port"
    end

    test "sets Application.put_env for endpoint with Bandit adapter" do
      content = live_app_content()
      assert content =~ "Application.put_env(:my_app, MyAppWeb.Endpoint"
      assert content =~ "adapter: Bandit.PhoenixAdapter"
    end

    test "endpoint config includes port from liveview_port env" do
      assert live_app_content() =~ "port: liveview_port"
    end

    test "endpoint config defaults to port 4200" do
      assert live_app_content() =~ "Application.get_env(:mob, :liveview_port, 4200)"
    end

    test "starts Mob.ComponentRegistry" do
      assert live_app_content() =~ "Mob.ComponentRegistry.start_link()"
    end

    test "embeds secret_key_base" do
      assert live_app_content() =~ "secret_key_base: \"#{@secret}\""
    end

    test "embeds signing_salt" do
      assert live_app_content() =~ "signing_salt: \"#{@salt}\""
    end
  end

  # ── erlang_entry_content/2 ────────────────────────────────────────────────────

  describe "erlang_entry_content/2" do
    test "has correct module declaration" do
      content = LiveViewPatcher.erlang_entry_content("MyApp", "my_app")
      assert content =~ "-module(my_app)."
    end

    test "exports start/0" do
      content = LiveViewPatcher.erlang_entry_content("MyApp", "my_app")
      assert content =~ "-export([start/0])."
    end

    test "calls MobApp module" do
      content = LiveViewPatcher.erlang_entry_content("MyApp", "my_app")
      assert content =~ "'Elixir.MyApp.MobApp':start()"
    end

    test "starts compiler, elixir, logger applications" do
      content = LiveViewPatcher.erlang_entry_content("MyApp", "my_app")
      assert content =~ "application:start(compiler)"
      assert content =~ "application:start(elixir)"
      assert content =~ "application:start(logger)"
    end
  end

  # ── mob_screen_content/1 ──────────────────────────────────────────────────────

  describe "mob_screen_content/1" do
    test "contains correct module name" do
      content = LiveViewPatcher.mob_screen_content("MyApp")
      assert content =~ "defmodule MyApp.MobScreen"
    end

    test "uses Mob.Screen" do
      content = LiveViewPatcher.mob_screen_content("MyApp")
      assert content =~ "use Mob.Screen"
    end

    test "renders a webview with Mob.LiveView.local_url" do
      content = LiveViewPatcher.mob_screen_content("MyApp")
      assert content =~ "Mob.UI.webview"
      assert content =~ "Mob.LiveView.local_url"
    end
  end

  # ── page_live_content/2 ───────────────────────────────────────────────────────

  describe "page_live_content/2" do
    test "uses correct web module" do
      content = LiveViewPatcher.page_live_content("MyApp", "my_app")
      assert content =~ "defmodule MyAppWeb.PageLive"
      assert content =~ "use MyAppWeb, :live_view"
    end

    test "has mount/3 assigning pong false" do
      content = LiveViewPatcher.page_live_content("MyApp", "my_app")
      assert content =~ "def mount"
      assert content =~ ":pong, false"
    end

    test "has ping handle_event that sets pong true" do
      content = LiveViewPatcher.page_live_content("MyApp", "my_app")
      assert content =~ ~s(handle_event("ping")
      assert content =~ ":pong, true"
    end

    test "template references app name in instructions" do
      content = LiveViewPatcher.page_live_content("MyApp", "my_app")
      assert content =~ "my_app_web/live/page_live.ex"
    end
  end

  # ── liveview_build_sh_content/2 ───────────────────────────────────────────────

  describe "liveview_build_sh_content/2" do
    defp build_sh, do: LiveViewPatcher.liveview_build_sh_content("MyApp", "my_app")

    test "is a bash script" do
      assert String.starts_with?(build_sh(), "#!/bin/bash")
    end

    test "copies all compiled deps with a glob loop" do
      assert build_sh() =~ "for lib_dir in _build/dev/lib/*/ebin"
    end

    test "crypto shim exports pbkdf2_hmac/5" do
      assert build_sh() =~ "pbkdf2_hmac/5"
    end

    test "crypto shim exports exor/2" do
      assert build_sh() =~ "exor/2"
    end

    test "crypto shim implements hmac_md5 using erlang:md5" do
      assert build_sh() =~ "hmac_md5"
      assert build_sh() =~ "erlang:md5"
    end

    test "xor_bytes uses recursive zip pattern" do
      assert build_sh() =~ "xor_bytes(A, B) -> xor_bytes(A, B, [])."
    end

    test "copies ssl from host OTP" do
      assert build_sh() =~ "Copying ssl from host OTP"
      assert build_sh() =~ "ssl.app"
    end

    test "builds and deploys Phoenix static assets" do
      content = build_sh()
      assert content =~ "mix assets.build"
      assert content =~ "priv/static"
    end

    test "spot-check verifies MobApp and MobScreen beams" do
      content = build_sh()
      assert content =~ "Elixir.MyApp.MobApp.beam"
      assert content =~ "Elixir.MyApp.MobScreen.beam"
    end

    test "uses app_name in BEAMS_DIR" do
      assert build_sh() =~ "OTP_ROOT/my_app"
    end

    test "uses module_name in swiftc module-name flag" do
      assert build_sh() =~ "-module-name MyApp"
    end
  end

  # ── mob_exs_content/2 ─────────────────────────────────────────────────────────

  describe "mob_exs_content/2" do
    test "contains mob_dir config" do
      content = LiveViewPatcher.mob_exs_content(~s("/path/to/mob"), ~s("/path/to/elixir/lib"))
      assert content =~ "mob_dir:"
    end

    test "contains elixir_lib config" do
      content = LiveViewPatcher.mob_exs_content(~s("/path/to/mob"), ~s("/path/to/elixir/lib"))
      assert content =~ "elixir_lib:"
    end

    test "contains liveview_port: 4200 (avoids conflict with host phx.server on 4000)" do
      content = LiveViewPatcher.mob_exs_content(~s("/path/to/mob"), ~s("/path/to/elixir/lib"))
      assert content =~ "liveview_port: 4200"
    end

    test "starts with import Config" do
      content = LiveViewPatcher.mob_exs_content(~s("/path/to/mob"), ~s("/path/to/elixir/lib"))
      assert content =~ "import Config"
    end
  end
end
