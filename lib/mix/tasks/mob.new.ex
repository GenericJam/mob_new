defmodule Mix.Tasks.Mob.New do
  use Mix.Task

  @shortdoc "Create a new Mob mobile app project"

  @moduledoc """
  Creates a new Mob project with Android and iOS boilerplate.

      mix mob.new APP_NAME [--no-install] [--no-ios] [--dest DIR] [--local]

  ## Options

    * `--no-install`   — skip running `mix deps.get` after generation
    * `--no-ios`       — skip iOS boilerplate (use on Linux or Android-only projects)
    * `--dest DIR`     — create project in DIR (default: current directory)
    * `--local`        — use `path:` deps pointing to local mob/mob_dev repos
                         instead of hex version constraints. **For Mob framework
                         contributors only** — not intended for app developers.
                         Paths resolved from `MOB_DIR` / `MOB_DEV_DIR` env vars,
                         falling back to `./mob` / `./mob_dev`, then `../mob` /
                         `../mob_dev`. Also pre-fills `mob.exs` with real paths
                         so `mix mob.install` skips path configuration prompts.

  ## What gets generated

      APP_NAME/
        mix.exs
        lib/APP_NAME/app.ex
        lib/APP_NAME/home_screen.ex
        android/
          settings.gradle
          build.gradle
          app/
            build.gradle
            src/main/
              AndroidManifest.xml
              java/com/mob/APP_NAME/MainActivity.kt
              java/com/mob/APP_NAME/MobBridge.kt
              java/com/mob/APP_NAME/MobNode.kt
              java/com/mob/APP_NAME/MobScannerActivity.kt
          gradle.properties
        ios/
          beam_main.m
          Info.plist

  After generation, run:

      cd APP_NAME
      mix mob.install    # icon generation + any first-run setup

  """

  @switches [no_install: :boolean, no_ios: :boolean, dest: :string, local: :boolean]

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
    local = opts[:local] || false
    no_ios = opts[:no_ios] || false

    if local do
      Mix.shell().info([:yellow, "* local mode: using path: deps for mob and mob_dev", :reset])
    end

    if no_ios do
      Mix.shell().info([:yellow, "* --no-ios: skipping iOS boilerplate", :reset])
    end

    Mix.shell().info([:green, "* creating ", :reset, project_dir])

    case MobNew.ProjectGenerator.generate(app_name, dest_dir, local: local, no_ios: no_ios) do
      {:error, reason} ->
        Mix.raise(reason)

      {:ok, project_dir} ->
        print_created_files(project_dir, app_name, no_ios)

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
    abs_dir = Path.expand(project_dir)

    case System.cmd(mix, ["deps.get"], cd: abs_dir, into: IO.stream()) do
      {_, 0} -> :ok
      {_, _} -> Mix.shell().info([:yellow, "* deps.get failed — run it manually inside #{project_dir}", :reset])
    end
  end

  defp print_created_files(project_dir, app_name, no_ios) do
    files = [
      "mix.exs",
      "lib/#{app_name}/app.ex",
      "lib/#{app_name}/home_screen.ex",
      "android/settings.gradle",
      "android/build.gradle",
      "android/app/build.gradle",
      "android/app/src/main/AndroidManifest.xml",
      "android/app/src/main/java/com/mob/#{app_name}/MainActivity.kt",
      "android/app/src/main/java/com/mob/#{app_name}/MobBridge.kt",
      "android/app/src/main/java/com/mob/#{app_name}/MobNode.kt",
      "android/app/src/main/java/com/mob/#{app_name}/MobScannerActivity.kt",
      "android/gradle.properties"
    ] ++ if(no_ios, do: [], else: ["ios/beam_main.m", "ios/Info.plist"])

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
