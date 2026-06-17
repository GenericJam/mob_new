defmodule Mix.Tasks.Mob.Adopt.Deps do
  @shortdoc "Adds :mob and :mob_dev to the project's mix.exs"

  @moduledoc """
  Adds Mob's two deps to the host project's `mix.exs`:

  - `{:mob, "~> 0.5"}` — the framework, used at runtime.
  - `{:mob_dev, "~> 0.3", only: :dev, runtime: false}` — build/deploy
    Mix tasks. Dev-only.

  ## Options

  - `--local` — write `path:` deps instead of Hex version constraints,
    resolved from `MOB_DIR` / `MOB_DEV_DIR` env vars (falling back to
    `./mob` / `../mob`). For Mob framework contributors.

  Other orchestrator flags accepted but inert.

  ## Idempotency

  Patching is done via `MobNew.LiveViewPatcher.inject_deps/3` (the
  same Sourceror-based AST walk `mix mob.new --liveview` uses), which
  short-circuits if `:mob` is already declared.

  Typically called by `mix mob.adopt`, not directly.
  """
  use Igniter.Mix.Task

  alias MobNew.{LiveViewPatcher, ProjectGenerator}

  @common_schema [
    ios: :boolean,
    android: :boolean,
    local: :boolean,
    python: :boolean,
    host_url: :string,
    live_view: :boolean
  ]
  @common_defaults [ios: true, android: true, live_view: true]

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :mob,
      example: "mix mob.adopt.deps",
      schema: @common_schema,
      defaults: @common_defaults
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    opts = igniter.args.options
    {mob_dep_str, mob_dev_dep_str, _, _} = ProjectGenerator.resolve_deps(opts)

    # Not `Igniter.Project.Deps.add_dep/3`: 0.8.1 renders 3-tuples with
    # trailing keyword opts as `:k => v` map syntax — invalid Elixir.
    Igniter.update_file(igniter, "mix.exs", fn source ->
      content = Rewrite.Source.get(source, :content)
      patched = LiveViewPatcher.inject_deps(content, mob_dep_str, mob_dev_dep_str)
      Rewrite.Source.update(source, :content, patched)
    end)
  end
end
