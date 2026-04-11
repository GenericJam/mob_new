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

  @templates_root :mob_new |> :code.priv_dir() |> Path.join("templates/mob.new")

  @doc """
  Returns the EEx template assigns map for `app_name`.
  """
  @spec assigns(String.t()) :: map()
  def assigns(app_name) do
    module_name  = Macro.camelize(app_name)
    display_name = module_name
    bundle_id    = "com.mob.#{app_name}"
    java_package = bundle_id
    lib_name     = String.replace(app_name, "_", "")
    java_path    = String.replace(bundle_id, ".", "/")

    %{
      app_name:     app_name,
      module_name:  module_name,
      display_name: display_name,
      bundle_id:    bundle_id,
      java_package: java_package,
      lib_name:     lib_name,
      java_path:    java_path
    }
  end

  @doc """
  Generates a new project at `dest_dir/<app_name>` from the bundled templates.

  Returns `{:ok, project_dir}` or `{:error, reason}`.
  """
  @spec generate(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def generate(app_name, dest_dir \\ ".") do
    project_dir = Path.join(dest_dir, app_name)

    if File.exists?(project_dir) do
      {:error, "Directory already exists: #{project_dir}"}
    else
      File.mkdir_p!(project_dir)
      a = assigns(app_name)
      render_templates(a, project_dir)
      {:ok, project_dir}
    end
  end

  # ── private ──────────────────────────────────────────────────────────────────

  defp render_templates(assigns, project_dir) do
    @templates_root
    |> find_templates()
    |> Enum.each(fn template_path ->
      rel = Path.relative_to(template_path, @templates_root)
      dest_rel = expand_path(rel, assigns)
      dest = Path.join(project_dir, dest_rel)
      File.mkdir_p!(Path.dirname(dest))
      content = EEx.eval_file(template_path, Map.to_list(assigns))
      File.write!(dest, content)
    end)
  end

  defp find_templates(dir) do
    Path.wildcard(Path.join(dir, "**/*.eex"))
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
