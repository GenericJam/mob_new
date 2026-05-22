defmodule Mix.Tasks.Mob.Install.Deps do
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

  `Igniter.Project.Deps.add_dep/3` is called with `on_exists: :skip`
  and short-circuits if the dep is already declared (any version).

  Typically called by `mix mob.install`, not directly.
  """
  use Igniter.Mix.Task

  alias Igniter.Project.Deps, as: ProjectDeps
  alias MobNew.ProjectGenerator

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
      example: "mix mob.install.deps",
      schema: @common_schema,
      defaults: @common_defaults
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    opts = igniter.args.options
    {mob_tuple, mob_dev_tuple} = dep_tuples(opts[:local] || false)

    igniter
    |> ProjectDeps.add_dep(mob_tuple, on_exists: :skip)
    |> ProjectDeps.add_dep(mob_dev_tuple, on_exists: :skip)
  end

  defp dep_tuples(true = _local) do
    mob_dir = ProjectGenerator.resolve_local_path("MOB_DIR", "mob")
    mob_dev_dir = ProjectGenerator.resolve_local_path("MOB_DEV_DIR", "mob_dev")
    {{:mob, [path: mob_dir]}, {:mob_dev, [path: mob_dev_dir, only: :dev, runtime: false]}}
  end

  defp dep_tuples(false = _local) do
    {{:mob, "~> 0.5"}, {:mob_dev, "~> 0.3", only: :dev, runtime: false}}
  end
end
