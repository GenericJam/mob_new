defmodule MobNew.ProjectGenerator do
  @moduledoc """
  Generates a new Mob project from EEx templates in `priv/templates/mob.new/`.

  ## Naming conventions

  Given `app_name = "my_cool_app"`:
    - `module_name`  → `"MyCoolApp"`
    - `display_name` → `"MyCoolApp"`
    - `bundle_id`    → `"com.mob.my_cool_app"`
    - `java_package` → `"com.mob.my_cool_app"`
    - `lib_name`     → `"mycoolapp"` (no underscores, for `System.loadLibrary`)
    - `java_path`    → `"com/mob/my_cool_app"` (for directory structure)
  """

  defp templates_root, do: :mob_new |> :code.priv_dir() |> Path.join("templates/mob.new")
  defp static_root,    do: :mob_new |> :code.priv_dir() |> Path.join("static/mob.new")

  @doc """
  Returns the EEx template assigns map for `app_name`.

  Options:
  - `:local` — when `true`, generates `path:` deps pointing to local mob/mob_dev
    repos instead of hex version constraints. Paths are resolved from the
    `MOB_DIR` and `MOB_DEV_DIR` environment variables, falling back to
    `../mob` and `../mob_dev` relative to the generated project location.
  """
  @spec assigns(String.t(), keyword()) :: map()
  def assigns(app_name, opts \\ []) do
    module_name  = Macro.camelize(app_name)
    display_name = module_name
    bundle_id    = "com.mob.#{app_name}"
    java_package = bundle_id
    lib_name     = String.replace(app_name, "_", "")
    java_path    = String.replace(bundle_id, ".", "/")

    # JNI method name segment: dots→underscores, then underscores→_1
    # e.g. "com.mob.test_app" → "com_mob_test_1app"
    jni_package =
      java_package
      |> String.replace("_", "_1")
      |> String.replace(".", "_")

    {mob_dep, mob_dev_dep, mob_exs_mob_dir, mob_exs_elixir_lib} = resolve_deps(opts)

    %{
      app_name:          app_name,
      module_name:       module_name,
      display_name:      display_name,
      bundle_id:         bundle_id,
      java_package:      java_package,
      jni_package:       jni_package,
      lib_name:          lib_name,
      java_path:         java_path,
      mob_dep:           mob_dep,
      mob_dev_dep:       mob_dev_dep,
      mob_exs_mob_dir:   mob_exs_mob_dir,
      mob_exs_elixir_lib: mob_exs_elixir_lib
    }
  end

  @doc """
  Generates a new project at `dest_dir/<app_name>` from the bundled templates.

  Returns `{:ok, project_dir}` or `{:error, reason}`.
  """
  @spec generate(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate(app_name, dest_dir \\ ".", opts \\ []) do
    project_dir = Path.join(dest_dir, app_name)

    if File.exists?(project_dir) do
      {:error, "Directory already exists: #{project_dir}"}
    else
      File.mkdir_p!(project_dir)
      a = assigns(app_name, opts)
      render_templates(a, project_dir, opts)
      copy_static(project_dir)
      {:ok, project_dir}
    end
  end

  @doc """
  Generates a LiveView-wrapped Mob project at `dest_dir/<app_name>`.

  This calls `mix phx.new` as a subprocess to create the Phoenix project, then:
  - Patches `mix.exs` to add the mob / mob_dev dependencies
  - Copies the standard Android/iOS native boilerplate
  - Applies the `mix mob.enable liveview` patches:
    - Injects `MobHook` into `assets/js/app.js`
    - Injects the bridge `<div>` into `root.html.heex`
    - Generates `lib/<app>/mob_screen.ex`
    - Writes `mob.exs` with `liveview_port: 4000`
  - Patches `lib/<app>/application.ex` to start `Mob.App` alongside Phoenix

  Returns `{:ok, project_dir}` or `{:error, reason}`.
  """
  @spec liveview_generate(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def liveview_generate(app_name, dest_dir \\ ".", opts \\ []) do
    project_dir = Path.join(Path.expand(dest_dir), app_name)

    if File.exists?(project_dir) do
      {:error, "Directory already exists: #{project_dir}"}
    else
      with :ok <- run_phx_new(app_name, dest_dir, opts),
           :ok <- patch_mix_exs(project_dir, opts),
           :ok <- copy_native_boilerplate(app_name, project_dir, opts),
           :ok <- apply_liveview_patches(app_name, project_dir, opts) do
        {:ok, project_dir}
      end
    end
  end

  # ── LiveView generation helpers ───────────────────────────────────────────────

  defp run_phx_new(app_name, dest_dir, _opts) do
    mix = System.find_executable("mix")

    unless mix do
      {:error, "mix executable not found in PATH"}
    else
      abs_dest = Path.expand(dest_dir)

      args = [
        "phx.new", app_name,
        "--no-install",
        "--no-dashboard",
        "--no-mailer",
        "--no-ecto"
      ]

      Mix.shell().info("Running mix phx.new #{app_name} in #{abs_dest}...")

      case System.cmd(mix, args, cd: abs_dest, stderr_to_stdout: true) do
        {_output, 0} ->
          :ok

        {output, exit_code} ->
          {:error, "mix phx.new failed (exit #{exit_code}):\n#{output}"}
      end
    end
  end

  defp patch_mix_exs(project_dir, opts) do
    path = Path.join(project_dir, "mix.exs")

    unless File.exists?(path) do
      {:error, "mix.exs not found in #{project_dir}"}
    else
      a = assigns(Path.basename(project_dir), opts)
      content = File.read!(path)
      patched = MobNew.LiveViewPatcher.inject_deps(content, a.mob_dep, a.mob_dev_dep)
      File.write!(path, patched)
      Mix.shell().info([:green, "* patch ", :reset, path, " (added mob deps)"])
      :ok
    end
  end

  defp copy_native_boilerplate(app_name, project_dir, opts) do
    # Render the native templates (android + ios) into a temp dir,
    # then move them into the Phoenix project dir.
    a = assigns(app_name, opts)
    no_ios = Keyword.get(opts, :no_ios, false)

    executable_templates = ["ios/build.sh"]
    executable_static    = ["android/gradlew"]

    templates_root()
    |> find_templates()
    |> Enum.filter(fn path ->
      rel = Path.relative_to(path, templates_root())
      String.starts_with?(rel, "android/") or
        (String.starts_with?(rel, "ios/") and not no_ios)
    end)
    |> Enum.each(fn template_path ->
      rel = Path.relative_to(template_path, templates_root())
      dest_rel = expand_path(rel, a)
      dest = Path.join(project_dir, dest_rel)
      File.mkdir_p!(Path.dirname(dest))
      content = EEx.eval_file(template_path, Map.to_list(a))
      File.write!(dest, content)
      Mix.shell().info([:green, "* create ", :reset, dest])

      if dest_rel in executable_templates, do: File.chmod!(dest, 0o755)
    end)

    # Copy Android static files (gradlew, wrapper jars, etc.)
    static_root()
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&File.dir?/1)
    |> Enum.filter(fn src ->
      rel = Path.relative_to(src, static_root())
      String.starts_with?(rel, "android/") or
        (String.starts_with?(rel, "ios/") and not no_ios)
    end)
    |> Enum.each(fn src ->
      rel = Path.relative_to(src, static_root())
      dest = Path.join(project_dir, rel)
      File.mkdir_p!(Path.dirname(dest))
      File.copy!(src, dest)
      if rel in executable_static, do: File.chmod!(dest, 0o755)
    end)

    :ok
  end

  defp apply_liveview_patches(app_name, project_dir, opts) do
    module_name = Macro.camelize(app_name)
    a = assigns(app_name, opts)

    # 1. Inject MobHook into assets/js/app.js
    patch_app_js(project_dir)

    # 2. Inject bridge element into root.html.heex
    patch_root_html(project_dir, app_name)

    # 3. Generate lib/<app>/mob_screen.ex
    generate_mob_screen(project_dir, app_name, module_name)

    # 4. Generate lib/<app>/mob_app.ex (BEAM entry point for LiveView mode)
    generate_mob_live_app(project_dir, app_name, module_name)

    # 5. Generate src/<app>.erl (Erlang bootstrap, calls MobApp.start/0)
    generate_erlang_entry(project_dir, app_name, module_name)

    # 6. Patch mix.exs to include src/ in erlc_paths
    patch_mix_exs_erlc(project_dir, app_name)

    # 7. Write mob.exs with liveview_port
    write_mob_exs(project_dir, a.mob_exs_mob_dir, a.mob_exs_elixir_lib)

    # 8. Write .gitignore entry for mob.exs (append if file exists)
    patch_gitignore(project_dir)

    # 9. Generate lib/<app>_web/live/page_live.ex and patch router
    #    (default get "/", PageController, :home fails on-device due to
    #    template compilation issues; a LiveView route works correctly)
    generate_page_live(project_dir, app_name, module_name)
    patch_router_to_liveview(project_dir, app_name)

    # 10. Overwrite ios/build.sh with the LiveView-specific version
    #     (different deps copy strategy, crypto shim, ssl copy, priv/static deploy)
    overwrite_liveview_build_sh(project_dir, app_name, module_name)

    :ok
  end

  defp patch_app_js(project_dir) do
    path = Path.join([project_dir, "assets", "js", "app.js"])

    if File.exists?(path) do
      content = File.read!(path)
      patched = MobNew.LiveViewPatcher.inject_mob_hook(content)
      File.write!(path, patched)
      Mix.shell().info([:green, "* patch ", :reset, path, " (added MobHook)"])
    else
      Mix.shell().info([:yellow, "* skip ", :reset, "assets/js/app.js not found — add MobHook manually"])
    end
  end

  defp patch_root_html(project_dir, app_name) do
    web_name = app_name <> "_web"
    candidates = [
      Path.join([project_dir, "lib", web_name, "components", "layouts", "root.html.heex"]),
      Path.join([project_dir, "lib", web_name, "templates", "layout", "root.html.heex"])
    ]

    path = Enum.find(candidates, &File.exists?/1)

    if path do
      content = File.read!(path)
      patched = MobNew.LiveViewPatcher.inject_mob_bridge_element(content)
      File.write!(path, patched)
      Mix.shell().info([:green, "* patch ", :reset, path, " (added mob-bridge element)"])
    else
      Mix.shell().info([:yellow, "* skip root.html.heex not found — add mob-bridge element manually:", :reset])
      Mix.shell().info("    " <> MobNew.LiveViewPatcher.mob_bridge_element())
    end
  end

  defp generate_mob_screen(project_dir, app_name, module_name) do
    dir  = Path.join([project_dir, "lib", app_name])
    path = Path.join(dir, "mob_screen.ex")
    File.mkdir_p!(dir)
    File.write!(path, MobNew.LiveViewPatcher.mob_screen_content(module_name))
    Mix.shell().info([:green, "* create ", :reset, path])
  end

  defp write_mob_exs(project_dir, mob_exs_mob_dir, mob_exs_elixir_lib) do
    path = Path.join(project_dir, "mob.exs")
    File.write!(path, MobNew.LiveViewPatcher.mob_exs_content(mob_exs_mob_dir, mob_exs_elixir_lib))
    Mix.shell().info([:green, "* create ", :reset, path])
  end

  defp generate_mob_live_app(project_dir, app_name, module_name) do
    dir  = Path.join([project_dir, "lib", app_name])
    path = Path.join(dir, "mob_app.ex")
    File.mkdir_p!(dir)
    # Extract the secret_key_base phx.new wrote into config/dev.exs so that
    # on-device Application.put_env uses the same key the dev server uses.
    # Falls back to a freshly generated key if extraction fails.
    secret_key_base = extract_secret_key_base(project_dir) || generate_secret_key_base()
    signing_salt    = generate_signing_salt()
    content = MobNew.LiveViewPatcher.mob_live_app_content(module_name, app_name, secret_key_base, signing_salt)
    File.write!(path, content)
    Mix.shell().info([:green, "* create ", :reset, path])
  end

  defp generate_page_live(project_dir, app_name, module_name) do
    dir  = Path.join([project_dir, "lib", "#{app_name}_web", "live"])
    path = Path.join(dir, "page_live.ex")
    File.mkdir_p!(dir)
    File.write!(path, MobNew.LiveViewPatcher.page_live_content(module_name, app_name))
    Mix.shell().info([:green, "* create ", :reset, path])
  end

  defp patch_router_to_liveview(project_dir, app_name) do
    web_name = app_name <> "_web"
    path = Path.join([project_dir, "lib", web_name, "router.ex"])

    if File.exists?(path) do
      content = File.read!(path)

      patched =
        Regex.replace(
          ~r/get\s+"\/",\s+PageController,\s+:home/,
          content,
          ~s(live "/", PageLive),
          global: false
        )

      if patched != content do
        File.write!(path, patched)
        Mix.shell().info([:green, "* patch ", :reset, path, " (live \"/\", PageLive)"])
      end
    end
  end

  defp overwrite_liveview_build_sh(project_dir, app_name, module_name) do
    path = Path.join([project_dir, "ios", "build.sh"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, MobNew.LiveViewPatcher.liveview_build_sh_content(module_name, app_name))
    File.chmod!(path, 0o755)
    Mix.shell().info([:green, "* create ", :reset, path, " (LiveView build.sh)"])
  end

  defp extract_secret_key_base(project_dir) do
    dev_exs = Path.join([project_dir, "config", "dev.exs"])

    if File.exists?(dev_exs) do
      content = File.read!(dev_exs)

      case Regex.run(~r/secret_key_base:\s*"([^"]{40,})"/, content) do
        [_, key] -> key
        _        -> nil
      end
    end
  end

  defp generate_secret_key_base do
    :crypto.strong_rand_bytes(48) |> Base.encode64(padding: false)
  end

  defp generate_signing_salt do
    :crypto.strong_rand_bytes(8) |> Base.encode64(padding: false)
  end

  defp generate_erlang_entry(project_dir, app_name, module_name) do
    dir  = Path.join(project_dir, "src")
    path = Path.join(dir, "#{app_name}.erl")
    File.mkdir_p!(dir)
    File.write!(path, MobNew.LiveViewPatcher.erlang_entry_content(module_name, app_name))
    Mix.shell().info([:green, "* create ", :reset, path])
  end

  defp patch_mix_exs_erlc(project_dir, _app_name) do
    # Phoenix projects don't compile .erl files by default. We need to add:
    #   erlc_paths: ["src"]
    # to the project/0 function so the Erlang bootstrap is compiled.
    path = Path.join(project_dir, "mix.exs")

    if File.exists?(path) do
      content = File.read!(path)

      if String.contains?(content, "erlc_paths") do
        Mix.shell().info("  * skip #{path} (erlc_paths already set)")
      else
        patched =
          Regex.replace(
            ~r/(def project do\s*\[)/,
            content,
            "\\1\n      erlc_paths: [\"src\"],\n      erlc_options: [:debug_info],",
            global: false
          )
        File.write!(path, patched)
        Mix.shell().info([:green, "* patch ", :reset, path, " (added erlc_paths: [\"src\"])"])
      end
    end
    :ok
  end

  defp patch_gitignore(project_dir) do
    path = Path.join(project_dir, ".gitignore")

    if File.exists?(path) do
      content = File.read!(path)

      unless String.contains?(content, "mob.exs") do
        File.write!(path, content <> "\n# Mob local config\nmob.exs\n")
        Mix.shell().info([:green, "* patch ", :reset, path, " (added mob.exs)"])
      end
    end
  end

  # ── Dep resolution ────────────────────────────────────────────────────────────

  defp resolve_deps(opts) do
    if opts[:local] do
      mob_dir     = resolve_local_path("MOB_DIR",     "mob")
      mob_dev_dir = resolve_local_path("MOB_DEV_DIR", "mob_dev")
      elixir_lib  = :code.lib_dir(:elixir) |> to_string() |> Path.dirname() |> Path.expand()

      mob_dep          = ~s({:mob,     path: "#{mob_dir}"})
      mob_dev_dep      = ~s({:mob_dev, path: "#{mob_dev_dir}", only: :dev, runtime: false})
      mob_exs_mob_dir  = inspect(mob_dir)
      mob_exs_elixir_lib = inspect(elixir_lib)

      {mob_dep, mob_dev_dep, mob_exs_mob_dir, mob_exs_elixir_lib}
    else
      mob_dep          = ~s({:mob,     "~> 0.2"})
      mob_dev_dep      = ~s({:mob_dev, "~> 0.2", only: :dev, runtime: false})
      mob_exs_mob_dir    = "Path.join(File.cwd!(), \"deps/mob\")"
      mob_exs_elixir_lib = "System.get_env(\"MOB_ELIXIR_LIB\", System.get_env(\"HOME\") <> \"/.local/share/mise/installs/elixir/1.18.4-otp-28/lib\")"

      {mob_dep, mob_dev_dep, mob_exs_mob_dir, mob_exs_elixir_lib}
    end
  end

  defp resolve_local_path(env_var, sibling_name) do
    cond do
      path = System.get_env(env_var) ->
        Path.expand(path)

      File.dir?(sibling = Path.expand("./#{sibling_name}")) ->
        sibling

      File.dir?(sibling = Path.expand("../#{sibling_name}")) ->
        sibling

      true ->
        Mix.raise("""
        Could not find local #{sibling_name} directory.
        Set #{env_var} env var or ensure #{sibling_name} exists alongside your project:
          export #{env_var}=/path/to/#{sibling_name}
        """)
    end
  end

  # ── private ──────────────────────────────────────────────────────────────────

  @executable_files ["ios/build.sh"]

  defp render_templates(assigns, project_dir, opts) do
    no_ios = Keyword.get(opts, :no_ios, false)

    templates_root()
    |> find_templates()
    |> Enum.reject(fn path ->
      no_ios and String.contains?(Path.relative_to(path, templates_root()), "ios/")
    end)
    |> Enum.each(fn template_path ->
      rel = Path.relative_to(template_path, templates_root())
      dest_rel = expand_path(rel, assigns)
      dest = Path.join(project_dir, dest_rel)
      File.mkdir_p!(Path.dirname(dest))
      content = EEx.eval_file(template_path, Map.to_list(assigns))
      File.write!(dest, content)
      if dest_rel in @executable_files, do: File.chmod!(dest, 0o755)
    end)
  end

  defp find_templates(dir) do
    Path.wildcard(Path.join(dir, "**/*.eex"), match_dot: true)
  end

  @executable_static ["android/gradlew"]

  defp copy_static(project_dir) do
    static_root()
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&File.dir?/1)
    |> Enum.each(fn src ->
      rel  = Path.relative_to(src, static_root())
      dest = Path.join(project_dir, rel)
      File.mkdir_p!(Path.dirname(dest))
      File.copy!(src, dest)
      if rel in @executable_static, do: File.chmod!(dest, 0o755)
    end)
  end

  # Replace `app_name` placeholder in directory segments and strip .eex extension.
  defp expand_path(rel, assigns) do
    rel
    |> String.replace("app_name", assigns.app_name)
    |> String.replace("java/", "java/#{assigns.java_path}/")
    |> strip_eex()
  end

  defp strip_eex(path) do
    if String.ends_with?(path, ".eex"),
      do: String.slice(path, 0..-5//1),
      else: path
  end
end
