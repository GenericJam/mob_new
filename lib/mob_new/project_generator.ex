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
      render_templates(a, project_dir)
      copy_static(project_dir)
      {:ok, project_dir}
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

  defp render_templates(assigns, project_dir) do
    templates_root()
    |> find_templates()
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
