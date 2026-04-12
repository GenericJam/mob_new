defmodule Mix.Tasks.Mob.New do
  use Mix.Task

  @shortdoc "Create a new Mob mobile app project"

  @moduledoc """
  Creates a new Mob project with Android and iOS boilerplate.

      mix mob.new APP_NAME [--no-install] [--dest DIR]

  ## Options

    * `--no-install`   — skip running `mix deps.get` after generation
    * `--dest DIR`     — create project in DIR (default: current directory)

  ## What gets generated

      APP_NAME/
        mix.exs
        lib/APP_NAME/app.ex
        lib/APP_NAME/hello_screen.ex
        android/
          settings.gradle
          build.gradle
          app/
            build.gradle
            src/main/
              AndroidManifest.xml
              java/com/mob/APP_NAME/MainActivity.java
        ios/
          beam_main.m
          Info.plist

  After generation, run:

      cd APP_NAME
      mix mob.install    # icon generation + any first-run setup

  """

  @switches [no_install: :boolean, dest: :string]

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, strict: @switches)

    app_name =
      case args do
        [name | _] -> name
        [] -> Mix.raise("Usage: mix mob.new APP_NAME")
      end

    unless valid_app_name?(app_name) do
      Mix.raise("App name must be lowercase letters, digits, and underscores only (e.g. my_app).")
    end

    dest_dir = opts[:dest] || "."
    project_dir = Path.join(dest_dir, app_name)

    Mix.shell().info([:green, "* creating ", :reset, project_dir])

    case MobNew.ProjectGenerator.generate(app_name, dest_dir) do
      {:error, reason} ->
        Mix.raise(reason)

      {:ok, project_dir} ->
        print_created_files(project_dir, app_name)

        unless opts[:no_install] do
          fetch_deps(project_dir)
        end

        print_next_steps(app_name, opts[:no_install])
    end
  end

  # ── private ──────────────────────────────────────────────────────────────────

  defp fetch_deps(project_dir) do
    Mix.shell().info("")
    Mix.shell().info("Fetching dependencies...")
    mix = System.find_executable("mix")

    case System.cmd(mix, ["deps.get"], cd: project_dir, into: IO.stream()) do
      {_, 0} -> :ok
      {_, _} -> Mix.shell().info([:yellow, "* deps.get failed — run it manually inside #{project_dir}", :reset])
    end
  end

  defp print_created_files(project_dir, app_name) do
    files = [
      "mix.exs",
      "lib/#{app_name}/app.ex",
      "lib/#{app_name}/hello_screen.ex",
      "android/settings.gradle",
      "android/build.gradle",
      "android/app/build.gradle",
      "android/app/src/main/AndroidManifest.xml",
      "android/app/src/main/java/com/mob/#{app_name}/MainActivity.java",
      "ios/beam_main.m",
      "ios/Info.plist"
    ]

    Enum.each(files, fn f ->
      Mix.shell().info([:green, "* creating ", :reset, Path.join(project_dir, f)])
    end)
  end

  defp print_next_steps(app_name, no_install) do
    install_hint =
      if no_install,
        do: "\n    mix deps.get",
        else: ""

    Mix.shell().info("""

    Your Mob app #{app_name} is ready!
    #{install_hint}
        cd #{app_name}
        mix mob.install                # generates app icon + first-run setup

    First deploy — edit mob.exs and android/local.properties with your local
    paths, then build native binaries (APK + iOS app), install on device,
    and push BEAMs:

        mix mob.deploy --native        # first time, or after native code changes

    Day-to-day development — just push changed BEAMs, no native rebuild needed:

        mix mob.deploy                 # fast push + restart
        mix mob.watch                  # auto-push on file save
    """)
  end

  defp valid_app_name?(name), do: Regex.match?(~r/^[a-z][a-z0-9_]*$/, name)
end
