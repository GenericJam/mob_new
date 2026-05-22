defmodule Mix.Tasks.Mob.Install do
  @shortdoc "Installs Mob into an existing Phoenix project"

  @moduledoc """
  Adds Mob (mobile framework) to an existing Phoenix-based Elixir project.

  Composable, [Igniter](https://hex.pm/packages/igniter)-based — mirrors
  the architecture of [team-alembic/phx_install](https://github.com/team-alembic/phx_install).
  This is the install-into-existing counterpart to `mix mob.new`, which
  generates a project from scratch. `mix mob.new` is unaffected by this task.

  ## Usage

      mix mob.install [OPTIONS]

  Run from inside an existing Mix project. The target project must
  declare `{:igniter, "~> 0.7", only: [:dev, :test]}` in its mix.exs
  (most modern Phoenix-ecosystem projects already do).

  ## Options

  - `--no-ios` — skip the iOS native tree
  - `--no-android` — skip the Android native tree
  - `--local` — `path:` deps for `:mob`/`:mob_dev`; pre-fill `mob.exs`
    paths from `MOB_DIR` / `MOB_DEV_DIR`. For Mob framework contributors.
  - `--python` — iOS-only: pre-configure embedded CPython via Pythonx
  - `--host-url URL` — write `config :mob, host_url: URL` so the
    generated `MobScreen` opens `URL` instead of the default
    `http://127.0.0.1:4000/`. Use for thin-client deployments where
    the WebView points at a deployed Phoenix server (fly.io etc.).
  - `--no-live-view` — skip the LiveView bridge patches
    (`assets/js/app.js` MobHook, `root.html.heex` bridge div) AND
    generate a thin-client `mob_app.ex` that does NOT boot Phoenix
    on-device. For Hologram-only or non-Phoenix hosts where the
    BEAM-on-device is just the native interop layer.

  Both platforms emit by default. Passing both `--no-ios` and
  `--no-android` raises.

  ## What gets installed

  - `:mob` + `:mob_dev` deps in `mix.exs`
  - `lib/<app>/mob_screen.ex` — `Mob.Screen` opening a WebView at
    `Application.get_env(:mob, :host_url)` (default localhost)
  - `mob.exs` — build-environment config
  - `.gitignore` updated to ignore `mob.exs`
  - `android/` and/or `ios/` native trees (gated by platform flags)
  - `lib/<app>/mob_app.ex` + `src/<app>.erl` for on-device BEAM entry
  - `erlc_paths`/`erlc_options` added to `mix.exs`

  Default (no `--no-live-view`):
  - `MobHook` injected into `assets/js/app.js`
  - bridge `<div>` injected into `root.html.heex`
  - `mob_app.ex` boots the host Phoenix endpoint on-device

  With `--no-live-view`:
  - LiveView bridge patches skipped
  - `mob_app.ex` is the thin-client variant (`use Mob.App` shell,
    no `Application.ensure_all_started`)

  ## Composability

  Every sub-installer is invokable independently:

      mix mob.install.deps          # just bump mix.exs
      mix mob.install.bridge        # just patch app.js + root.html.heex
      mix mob.install.screen        # just generate mob_screen.ex
      mix mob.install.mob_app       # just generate mob_app.ex + .erl bootstrap
      mix mob.install.mob_exs       # just write mob.exs + .gitignore
      mix mob.install.native        # both native trees
      mix mob.install.native.android
      mix mob.install.native.ios
      mix mob.install.finalize      # post-install notice (no file changes)

  Each accepts the same flags as `mob.install` and respects them
  individually. Run `mix help mob.install.<sub>` for sub-task docs.

  On-device runtime services (`Mob.ComponentRegistry`,
  `Mob.NativeLogger`, etc.) start imperatively inside
  `<App>.MobApp.start/0` — `Mob.App` is the *behaviour* the device
  entry uses (via `use Mob.App`), never a supervision-tree child.
  """
  use Igniter.Mix.Task

  alias Mix.Tasks.Mob.Install.{Bridge, Deps, Finalize, MobApp, MobExs, Native, Screen}

  @schema [
    ios: :boolean,
    android: :boolean,
    local: :boolean,
    python: :boolean,
    host_url: :string,
    live_view: :boolean
  ]

  @defaults [ios: true, android: true, live_view: true]

  @doc false
  def common_schema, do: @schema
  @doc false
  def common_defaults, do: @defaults

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :mob,
      example: "mix mob.install --host-url https://my-app.fly.dev/",
      schema: @schema,
      defaults: @defaults,
      composes: [
        "mob.install.deps",
        "mob.install.bridge",
        "mob.install.screen",
        "mob.install.mob_app",
        "mob.install.mob_exs",
        "mob.install.native",
        "mob.install.finalize"
      ]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    ensure_archive_path_loaded()
    validate_platforms!(igniter.args.options)
    argv = igniter.args.argv || []

    # Sub-tasks are dispatched by module atom rather than by task-name
    # string. `Igniter.compose_task/4` accepts either, but the atom form
    # uses `Code.ensure_compiled!/1` directly instead of routing through
    # `Mix.Task.get/1` — which is what lets this orchestrator work when
    # `mob_new` is installed as a Mix archive. (Archive-resident task
    # modules aren't findable through `Mix.Task.get/1`, but they ARE
    # findable through the code path once we've put the archive's ebin
    # on it via `ensure_archive_path_loaded/0` above.)
    igniter
    |> Igniter.compose_task(Deps, argv)
    |> Igniter.compose_task(Bridge, argv)
    |> Igniter.compose_task(Screen, argv)
    |> Igniter.compose_task(MobApp, argv)
    |> Igniter.compose_task(MobExs, argv)
    |> Igniter.compose_task(Native, argv)
    |> Igniter.compose_task(Finalize, argv)
  end

  defp validate_platforms!(opts) do
    if Keyword.get(opts, :ios, true) == false and Keyword.get(opts, :android, true) == false do
      Mix.raise("Cannot pass both --no-ios and --no-android; at least one platform must remain.")
    end
  end

  # When `mob_new` is installed as a Mix archive, Mix loads this module
  # by resolving its BEAM path directly from the archive's `.app` file
  # rather than via the Erlang code path. Sibling modules in the same
  # archive (the sub-installers) are therefore not findable via
  # `Code.ensure_compiled/1` until we put the archive's ebin on the
  # code path. `:code.which(__MODULE__)` gives us this BEAM's directory;
  # `:code.add_patha/1` is idempotent (no-op when already present), so
  # non-archive distributions (path/Hex dep) are unaffected.
  #
  # Inlined here rather than calling a `MobNew.*` helper because that
  # helper would itself be archive-resident and therefore unreachable
  # at the moment this fix needs to run.
  defp ensure_archive_path_loaded do
    case :code.which(__MODULE__) do
      path when is_list(path) ->
        path |> Path.dirname() |> String.to_charlist() |> :code.add_patha()
        :ok

      _ ->
        :ok
    end
  end
end
