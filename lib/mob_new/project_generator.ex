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
  """
  @spec assigns(String.t()) :: map()
  def assigns(app_name) do
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

    %{
      app_name:     app_name,
      module_name:  module_name,
      display_name: display_name,
      bundle_id:    bundle_id,
      java_package: java_package,
      jni_package:  jni_package,
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
      copy_static(project_dir)
      {:ok, project_dir}
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
