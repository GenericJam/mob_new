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
      result =
        LiveViewPatcher.inject_deps(
          @sample_mix_exs,
          ~s({:mob, "~> 0.2"}),
          ~s({:mob_dev, "~> 0.2", only: :dev})
        )

      assert result =~ ~s({:mob, "~> 0.2"})
    end

    test "injects mob_dev dep into deps function" do
      result =
        LiveViewPatcher.inject_deps(
          @sample_mix_exs,
          ~s({:mob, "~> 0.2"}),
          ~s({:mob_dev, "~> 0.2", only: :dev})
        )

      assert result =~ ~s({:mob_dev, "~> 0.2", only: :dev})
    end

    test "preserves existing deps" do
      result =
        LiveViewPatcher.inject_deps(
          @sample_mix_exs,
          ~s({:mob, "~> 0.2"}),
          ~s({:mob_dev, "~> 0.2", only: :dev})
        )

      assert result =~ ~s({:phoenix, "~> 1.7"})
      assert result =~ ~s({:ecto, "~> 3.0"})
    end

    test "is idempotent — does not double-inject if :mob already present" do
      once =
        LiveViewPatcher.inject_deps(
          @sample_mix_exs,
          ~s({:mob, "~> 0.2"}),
          ~s({:mob_dev, "~> 0.2", only: :dev})
        )

      twice =
        LiveViewPatcher.inject_deps(
          once,
          ~s({:mob, "~> 0.2"}),
          ~s({:mob_dev, "~> 0.2", only: :dev})
        )

      assert once == twice
    end
  end

  # ── mob_live_app_content/4 ────────────────────────────────────────────────────

  describe "mob_live_app_content/4" do
    @secret "testSecretKeyBase1234567890abcdefghijklmnopqrstuvwxyz"
    @salt "testSalt"

    defp live_app_content,
      do: LiveViewPatcher.mob_live_app_content("MyApp", "my_app", @secret, @salt)

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

    test "honors MOB_SIM_RUNTIME_DIR env var (regression: must not hardcode /tmp)" do
      # Native template at priv/templates/mob.new/ios/build.sh.eex respects
      # MOB_SIM_RUNTIME_DIR with ~/.mob/runtime/ios-sim default; the LV path
      # used to hardcode /tmp/otp-ios-sim, so `mix mob.deploy --native` synced
      # OTP into ~/.mob/runtime/ios-sim while build.sh wrote /tmp/otp-ios-sim
      # — the two halves disagreed and the simulator never saw fresh BEAMs.
      content = build_sh()
      assert content =~ ~s(RUNTIME_DIR="${MOB_SIM_RUNTIME_DIR:-$HOME/.mob/runtime/ios-sim}")
      refute content =~ "/tmp/otp-ios-sim",
             "build.sh hardcodes /tmp/otp-ios-sim — should use $RUNTIME_DIR"
    end

    test "all runtime-dir uses go through $RUNTIME_DIR" do
      # Pins the rsync sync target, the logo-copy targets, and the priv/static
      # rsync target — every spot that previously used /tmp/otp-ios-sim.
      content = build_sh()
      assert content =~ ~s(rsync -a --delete --no-perms "$OTP_ROOT/" "$RUNTIME_DIR/")
      assert content =~ ~s($RUNTIME_DIR/mob_logo_dark.png)
      assert content =~ ~s($RUNTIME_DIR/mob_logo_light.png)
      assert content =~ ~s($RUNTIME_DIR/my_app/priv/)
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

  # ── mob_live_app_content/4 — Ecto additions ───────────────────────────────────

  describe "mob_live_app_content/4 ecto additions" do
    defp live_app do
      LiveViewPatcher.mob_live_app_content("MyApp", "my_app", "secret", "salt")
    end

    test "starts ecto_sqlite3 before the app" do
      content = live_app()
      assert content =~ "ensure_all_started(:ecto_sqlite3)"
      ecto_pos = :binary.match(content, "ensure_all_started(:ecto_sqlite3)") |> elem(0)
      app_pos = :binary.match(content, "ensure_all_started(:my_app)") |> elem(0)
      assert ecto_pos < app_pos
    end

    test "runs Ecto.Migrator after app start" do
      content = live_app()
      assert content =~ "Ecto.Migrator.with_repo(MyApp.Repo"
      assert content =~ "Ecto.Migrator.run"
      assert content =~ ":up, all: true"
    end

    test "has migrations_dir/0 that reads MOB_BEAMS_DIR" do
      content = live_app()
      assert content =~ "defp migrations_dir"
      assert content =~ "MOB_BEAMS_DIR"
    end
  end

  # ── repo_content/2 ────────────────────────────────────────────────────────────

  describe "repo_content/2" do
    defp repo, do: LiveViewPatcher.repo_content("MyApp", "my_app")

    test "has correct module name and otp_app" do
      assert repo() =~ "defmodule MyApp.Repo"
      assert repo() =~ "otp_app: :my_app"
      assert repo() =~ "Ecto.Adapters.SQLite3"
    end

    test "init/2 reads MOB_DATA_DIR" do
      assert repo() =~ "MOB_DATA_DIR"
      assert repo() =~ "app.db"
    end

    test "init/2 sets pool_size: 1" do
      assert repo() =~ "pool_size: 1"
    end
  end

  # ── note_content/1 ────────────────────────────────────────────────────────────

  describe "note_content/1" do
    test "has correct module and schema" do
      content = LiveViewPatcher.note_content("MyApp")
      assert content =~ "defmodule MyApp.Note"
      assert content =~ ~s(schema "notes")
      assert content =~ "field :title"
      assert content =~ "field :body"
    end
  end

  # ── notes_content/2 ───────────────────────────────────────────────────────────

  describe "notes_content/2" do
    defp notes, do: LiveViewPatcher.notes_content("MyApp", "my_app")

    test "has correct module and alias" do
      assert notes() =~ "defmodule MyApp.Notes"
      assert notes() =~ "alias MyApp.{Repo, Note}"
    end

    test "has list/0, get/1, create/0, update/2, delete/1" do
      content = notes()
      assert content =~ "def list"
      assert content =~ "def get(id)"
      assert content =~ "def create"
      assert content =~ "def update(id"
      assert content =~ "def delete(id)"
    end

    test "seeds on first load" do
      assert notes() =~ "maybe_seed"
      assert notes() =~ "Welcome to Mob"
    end
  end

  # ── migration_content/0 ───────────────────────────────────────────────────────

  describe "migration_content/1" do
    test "creates notes table with title and body" do
      content = LiveViewPatcher.migration_content("my_app")
      assert content =~ "MyApp.Repo.Migrations.CreateNotes"
      assert content =~ "create table(:notes)"
      assert content =~ "add :title"
      assert content =~ "add :body"
    end
  end

  # ── notes_list_live_content/2 ─────────────────────────────────────────────────

  describe "notes_list_live_content/2" do
    defp nll, do: LiveViewPatcher.notes_list_live_content("MyApp", "my_app")

    test "correct module and alias" do
      assert nll() =~ "defmodule MyAppWeb.NotesListLive"
      assert nll() =~ "alias MyApp.Notes"
    end

    test "mounts with notes list" do
      assert nll() =~ "Notes.list()"
    end

    test "handles new_note, open, delete events" do
      content = nll()
      assert content =~ ~s("new_note")
      assert content =~ ~s("open")
      assert content =~ ~s("delete")
    end
  end

  # ── note_editor_live_content/2 ────────────────────────────────────────────────

  describe "note_editor_live_content/2" do
    defp nel, do: LiveViewPatcher.note_editor_live_content("MyApp", "my_app")

    test "correct module and alias" do
      assert nel() =~ "defmodule MyAppWeb.NoteEditorLive"
      assert nel() =~ "alias MyApp.Notes"
    end

    test "mounts with note by id" do
      assert nel() =~ ~s(%{"id" => id})
      assert nel() =~ "Notes.get(id)"
    end

    test "handles update_note event" do
      assert nel() =~ ~s("update_note")
      assert nel() =~ "Notes.update"
    end

    test "has word count" do
      assert nel() =~ "word_count"
      assert nel() =~ "count_words"
    end
  end

  # ── about_live_content/2 ──────────────────────────────────────────────────────

  describe "about_live_content/2" do
    defp about, do: LiveViewPatcher.about_live_content("MyApp", "my_app")

    test "correct module" do
      assert about() =~ "defmodule MyAppWeb.AboutLive"
    end

    test "shows OTP release and Elixir version" do
      content = about()
      assert content =~ "system_info(:otp_release)"
      assert content =~ "System.version()"
    end

    test "shows notes count via Notes.list()" do
      assert about() =~ "MyApp.Notes.list() |> length()"
    end

    test "handles name editing events" do
      content = about()
      assert content =~ ~s("edit_name")
      assert content =~ ~s("save_name")
    end
  end
end
