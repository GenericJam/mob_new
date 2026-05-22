defmodule MobNew.ProjectGenerator do
  @moduledoc """
  Generates a new Mob project from EEx templates in `priv/templates/mob.new/`.

  ## Naming conventions

  Given `app_name = "my_cool_app"` and the default bundle prefix:
    - `module_name`  → `"MyCoolApp"`
    - `display_name` → `"MyCoolApp"`
    - `bundle_id`    → `"com.example.my_cool_app"`
    - `java_package` → `"com.example.my_cool_app"`
    - `lib_name`     → `"mycoolapp"` (no underscores, for `System.loadLibrary`)
    - `java_path`    → `"com/example/my_cool_app"` (for directory structure)

  ## Bundle prefix

  The reverse-DNS prefix for the bundle ID defaults to `com.example`, the
  universal "must change before shipping" placeholder. Override at generation
  time with the `MOB_BUNDLE_PREFIX` env var:

      MOB_BUNDLE_PREFIX=net.acme mix mob.new my_cool_app
      # → bundle_id = "net.acme.my_cool_app"

  We deliberately do **not** use `com.mob` — that's our reverse-DNS namespace,
  and Apple/Google enforce ownership at submission time, so a project that
  ships with `com.mob.*` would have to be renamed before reaching either store.
  """

  # Template + static roots. Default to the installed archive's priv dir
  # (the loaded mob_new code's :code.priv_dir/1). When the caller asks for
  # local-override behaviour AND a usable mob_new checkout is reachable,
  # use that checkout's priv instead — so `mix mob.new --local` picks up
  # template fixes that haven't been republished to the archive yet.
  #
  # Mob_new's archive install pattern means the templates baked into the
  # archive get stale the moment someone commits a template fix in the
  # repo. `--local` was originally documented as "use path: deps for
  # mob/mob_dev" only, but users (rightly) expected it to also pick up
  # local template fixes — same mental model as `--local` everywhere
  # else in the Mix ecosystem.
  @doc false
  @spec templates_root(keyword()) :: String.t()
  def templates_root(opts), do: priv_root(opts) |> Path.join("templates/mob.new")

  @doc false
  @spec static_root(keyword()) :: String.t()
  def static_root(opts), do: priv_root(opts) |> Path.join("static/mob.new")

  defp priv_root(opts) do
    case local_mob_new_priv(opts) do
      nil -> :code.priv_dir(:mob_new) |> to_string()
      dir -> dir
    end
  end

  # Returns the priv path of a local mob_new checkout when:
  #   1. `opts[:local]` is truthy (user opted in), AND
  #   2. an override path is reachable: `$MOB_NEW_DIR` env var or
  #      `$HOME/code/mob_new` as the fallback location, AND
  #   3. that path actually contains `priv/templates/mob.new/`.
  # Otherwise returns nil (caller falls back to :code.priv_dir/1).
  #
  # Public for testing — same pattern as other "decide which fixture to
  # use" helpers we expose so tests can stub the env independently of the
  # filesystem.
  @doc false
  @spec local_mob_new_priv(keyword()) :: String.t() | nil
  def local_mob_new_priv(opts) do
    if Keyword.get(opts, :local, false) do
      [System.get_env("MOB_NEW_DIR"), Path.expand("~/code/mob_new")]
      |> Enum.reject(&is_nil/1)
      |> Enum.find_value(&priv_if_templates_exist/1)
    end
  end

  defp priv_if_templates_exist(dir) do
    priv = Path.join(dir, "priv")
    if File.dir?(Path.join(priv, "templates/mob.new")), do: priv
  end

  # Reverse-DNS prefix for the generated bundle id. Honors MOB_BUNDLE_PREFIX
  # (typical value: "com.acme" or "net.you"); defaults to "com.example", the
  # universal "must change before shipping" placeholder. Never defaults to
  # "com.mob" — Apple and Google enforce reverse-DNS ownership at App Store
  # / Play Store submission, so apps generated with our namespace would have
  # to be renamed before reaching either store.
  @spec bundle_prefix() :: String.t()
  def bundle_prefix do
    case System.get_env("MOB_BUNDLE_PREFIX") do
      nil -> "com.example"
      "" -> "com.example"
      raw -> String.trim(raw)
    end
  end

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
    module_name = Macro.camelize(app_name)
    display_name = module_name
    bundle_prefix = bundle_prefix()
    bundle_id = "#{bundle_prefix}.#{app_name}"
    java_package = bundle_id
    lib_name = String.replace(app_name, "_", "")
    java_path = String.replace(bundle_id, ".", "/")

    # JNI method name segment: dots→underscores, then underscores→_1
    # e.g. "com.mob.test_app" → "com_mob_test_1app"
    jni_package =
      java_package
      |> String.replace("_", "_1")
      |> String.replace(".", "_")

    {mob_dep, mob_dev_dep, mob_exs_mob_dir, mob_exs_elixir_lib} = resolve_deps(opts)

    %{
      app_name: app_name,
      module_name: module_name,
      display_name: display_name,
      bundle_id: bundle_id,
      java_package: java_package,
      jni_package: jni_package,
      lib_name: lib_name,
      java_path: java_path,
      mob_dep: mob_dep,
      mob_dev_dep: mob_dev_dep,
      mob_exs_mob_dir: mob_exs_mob_dir,
      mob_exs_elixir_lib: mob_exs_elixir_lib,
      ndk_version: MobNew.NdkVersion.recommended(),
      python: Keyword.get(opts, :python, false)
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
      copy_static(project_dir, opts)
      write_dotfiles(project_dir, opts)
      if Keyword.get(opts, :python, false), do: apply_python_patches(project_dir, app_name)
      {:ok, project_dir}
    end
  end

  @doc """
  Patches a generated project to enable Pythonx (embedded CPython,
  iOS + Android).

  Two patches:
    * `mix.exs` — adds `{:pythonx, "~> 0.4"}` to deps.
    * `lib/<app>/python_paths.ex` — pure detection module that reads
      `:code.root_dir/0` for iOS and `MOB_PYTHON_HOME` / `MOB_PYTHON_DL`
      env vars (set by Android's `MainActivity`) for Android. Returns
      `:desktop` / `{:ios, paths}` / `{:android, paths}` /
      `{:partial, missing}`.

  Note: deliberately does NOT patch `config/config.exs` — `:pythonx,
  :uv_init` in compile-time config makes `Pythonx.Application.start/2`
  auto-run uv at boot, which fails on device. The generated `app.ex`
  (when --python is set) inlines the pyproject_toml and calls
  `Pythonx.Uv.fetch + init` only on the `:desktop` branch.

  Mirrors `mix mob.enable pythonx` (in `mob_dev`). Idempotent — safe to
  run twice. Public for testing.
  """
  @spec apply_python_patches(String.t(), String.t()) :: :ok
  def apply_python_patches(project_dir, app_name) do
    add_pythonx_dep(project_dir)
    write_python_paths_module(project_dir, app_name)
    :ok
  end

  defp add_pythonx_dep(project_dir) do
    path = Path.join(project_dir, "mix.exs")

    case File.read(path) do
      {:ok, content} ->
        cond do
          String.contains?(content, ":pythonx") ->
            :ok

          Regex.match?(Regex.compile!(~S{defp\s+deps\s+do\s*\[}), content) ->
            patched =
              Regex.replace(
                Regex.compile!(~S{(defp\s+deps\s+do\s*\[)}),
                content,
                ~s(\\1\n      {:pythonx, "~> 0.4"},),
                global: false
              )

            File.write!(path, patched)

          true ->
            :ok
        end

      _ ->
        :ok
    end
  end

  defp write_python_paths_module(project_dir, app_name) do
    module_name = Macro.camelize(app_name)
    dir = Path.join([project_dir, "lib", app_name])
    File.mkdir_p!(dir)
    path = Path.join(dir, "python_paths.ex")

    unless File.exists?(path) do
      File.write!(path, python_paths_module_source(module_name))
    end
  end

  defp python_paths_module_source(module_name) do
    """
    defmodule #{module_name}.PythonPaths do
      @moduledoc \"\"\"
      Detects bundled CPython at runtime and reports the paths needed
      for `Pythonx.init/4` (dl_path, home_path, stdlib_path).

      Pure detection logic — see your app's `App` module for how the
      result is fed into `Pythonx.init/4` at boot.

      ## Per-platform layout

        * **iOS**: `mix mob.deploy --native` bundles `Python.framework`,
          stdlib, and lib-dynload at `<App>.app/otp/python/`. Detection
          reads `:code.root_dir/0` and inspects that subtree.

        * **Android**: `mix mob.deploy --native` bundles libpython.so
          into the APK's `jniLibs/<abi>/` (auto-extracted by the
          installer to `applicationInfo.nativeLibraryDir`) and stdlib
          + lib-dynload into `assets/python/` (extracted to
          `filesDir/python/` by `MainActivity.onCreate` on first
          launch). MainActivity exports the resolved paths via
          `MOB_PYTHON_DL` and `MOB_PYTHON_HOME` env vars before
          starting the BEAM.

      ## Returns

        * `:desktop` — no platform bundle found; the caller should
          drive `Pythonx.Uv.fetch + init` manually.
        * `{:ios, paths}` / `{:android, paths}` — bundle present; pass
          into `Pythonx.init/4`.
        * `{:partial, missing}` — bundle is incomplete; surface to
          the user.
      \"\"\"

      @type python_paths :: %{
              dl_path: String.t(),
              home_path: String.t(),
              stdlib_path: String.t()
            }

      @type detection ::
              :desktop
              | {:ios, python_paths()}
              | {:android, python_paths()}
              | {:partial, [atom()]}

      @python_version "python3.13"

      @spec detect(String.t()) :: detection()
      def detect(otp_root) when is_binary(otp_root) do
        cond do
          android_paths() != nil ->
            paths = android_paths()

            case missing(paths) do
              [] -> {:android, paths}
              missing -> {:partial, missing}
            end

          File.dir?(Path.join(otp_root, "python")) ->
            paths = build_ios_paths(otp_root)

            case missing(paths) do
              [] -> {:ios, paths}
              missing -> {:partial, missing}
            end

          true ->
            :desktop
        end
      end

      @spec build_ios_paths(String.t()) :: python_paths()
      def build_ios_paths(otp_root) when is_binary(otp_root) do
        python_dir = Path.join(otp_root, "python")

        %{
          dl_path: Path.join([python_dir, "Python.framework", "Python"]),
          home_path: python_dir,
          stdlib_path: Path.join([python_dir, "lib", @python_version])
        }
      end

      @spec build_android_paths() :: python_paths() | nil
      def build_android_paths do
        case {System.get_env("MOB_PYTHON_DL"), System.get_env("MOB_PYTHON_HOME")} do
          {dl, home} when is_binary(dl) and is_binary(home) ->
            %{
              dl_path: dl,
              home_path: home,
              stdlib_path: Path.join([home, "lib", @python_version])
            }

          _ ->
            nil
        end
      end

      defp android_paths, do: build_android_paths()

      @spec missing(python_paths()) :: [atom()]
      def missing(%{dl_path: dl, home_path: home, stdlib_path: stdlib}) do
        [
          {:dl_path, File.exists?(dl)},
          {:home_path, File.dir?(home)},
          {:stdlib_path, File.dir?(stdlib)}
        ]
        |> Enum.reject(fn {_, present?} -> present? end)
        |> Enum.map(&elem(&1, 0))
      end
    end
    """
  end

  # `mix archive.build` packages files in `priv/` via `Path.wildcard/2`
  # without `match_dot: true`, which silently drops every dotfile in
  # the template tree. We sidestep that by writing them inline here so
  # the archive packaging never has to know about them. If you need
  # variable substitution in a future dotfile, switch to a non-dot
  # template name (e.g. `dot_tool_versions.eex`) and rename in
  # `expand_path/2` rather than relying on the archive to ship `.eex`
  # dotfiles directly.
  @dotfiles %{
    "android/.editorconfig" => """
    # ktlint configuration for Mob-generated Android projects.
    #
    # package-name: Mob app names use underscores (e.g. my_app → com.example.my_app).
    #   Android allows underscores in package names; the style guide discourages them
    #   but the Mob naming convention requires them.
    #
    # function-naming: JNI bridge functions (nativeSetActivity, nativeStartBeam, etc.)
    #   must match the JNI symbol names declared in beam_jni.c. Renaming them to
    #   camelCase would break the native linkage.
    #
    # no-multi-spaces: Mob templates use column-aligned arrows in when expressions
    #   for readability. ktlint cannot auto-correct this, so we suppress it globally.
    [*.kt]
    ktlint_standard_package-name = disabled
    ktlint_standard_function-naming = disabled
    ktlint_standard_no-multi-spaces = disabled
    """,
    ".tool-versions" => """
    # Pinned toolchain versions for Mob development.
    # Both mise and asdf read this file automatically.
    #
    #   mise install    https://mise.jdx.dev  (recommended — brew install mise)
    #   asdf install    https://asdf-vm.com
    #
    # OTP 29 matches the device runtime tarballs. Java 17 LTS is required for Gradle.
    erlang 29.0
    elixir 1.20.0-rc.5-otp-29
    java temurin-17.0.18
    """,
    ".formatter.exs" => """
    [
      plugins: [Mob.Formatter],
      inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
    ]
    """,
    ".gitignore" => """
    /_build/
    /deps/
    /doc/
    /.fetch
    *.ez
    *.beam
    mob.exs
    android/local.properties
    android/.gradle/
    android/app/build/
    """
  }

  defp write_dotfiles(project_dir, opts) do
    no_android = Keyword.get(opts, :no_android, false)
    no_ios = Keyword.get(opts, :no_ios, false)

    Enum.each(@dotfiles, fn {name, content} ->
      skip =
        (no_android and String.starts_with?(name, "android/")) or
          (no_ios and String.starts_with?(name, "ios/"))

      unless skip do
        File.write!(Path.join(project_dir, name), content)
      end
    end)
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
  @spec liveview_generate(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def liveview_generate(app_name, dest_dir \\ ".", opts \\ []) do
    project_dir = Path.join(Path.expand(dest_dir), app_name)

    if File.exists?(project_dir) do
      {:error, "Directory already exists: #{project_dir}"}
    else
      # Mark this as a liveview generation so copy_native_boilerplate skips
      # files Phoenix's `mix phx.new` already created (mix.exs, config/, etc.).
      liveview_opts = Keyword.put(opts, :liveview, true)

      with :ok <- run_phx_new(app_name, dest_dir, opts),
           :ok <- patch_mix_exs(project_dir, opts),
           :ok <- copy_native_boilerplate(app_name, project_dir, liveview_opts),
           :ok <- apply_liveview_patches(app_name, project_dir, opts) do
        {:ok, project_dir}
      end
    end
  end

  # ── LiveView generation helpers ───────────────────────────────────────────────

  defp run_phx_new(app_name, dest_dir, _opts) do
    mix = System.find_executable("mix")

    if mix do
      abs_dest = Path.expand(dest_dir)

      args = [
        "phx.new",
        app_name,
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
    else
      {:error, "mix executable not found in PATH"}
    end
  end

  defp patch_mix_exs(project_dir, opts) do
    path = Path.join(project_dir, "mix.exs")

    if File.exists?(path) do
      a = assigns(Path.basename(project_dir), opts)
      content = File.read!(path)
      patched = MobNew.LiveViewPatcher.inject_deps(content, a.mob_dep, a.mob_dev_dep)
      File.write!(path, patched)
      Mix.shell().info([:green, "* patch ", :reset, path, " (added mob deps)"])
      :ok
    else
      {:error, "mix.exs not found in #{project_dir}"}
    end
  end

  defp copy_native_boilerplate(app_name, project_dir, opts) do
    # Render the native templates (android + ios) into a temp dir,
    # then move them into the Phoenix project dir.
    a = assigns(app_name, opts)
    no_ios = Keyword.get(opts, :no_ios, false)
    no_android = Keyword.get(opts, :no_android, false)

    # iOS sim build.sh.eex was eliminated in Phase 2 iter 13b — Mix is now
    # the sole orchestrator for iOS sim builds. LiveView still emits a
    # build.sh dynamically (iter 13c will eliminate that too).
    executable_templates = []
    executable_static = ["android/gradlew"]

    t_root = templates_root(opts)
    s_root = static_root(opts)
    log_local_priv_once(opts, t_root)

    t_root
    |> find_templates()
    |> Enum.filter(&platform_included?(&1, t_root, no_ios, no_android))
    |> Enum.reject(&liveview_phoenix_owned?(&1, t_root, opts))
    |> Enum.each(fn template_path ->
      rel = Path.relative_to(template_path, t_root)
      dest_rel = expand_path(rel, a)
      dest = Path.join(project_dir, dest_rel)
      File.mkdir_p!(Path.dirname(dest))
      content = EEx.eval_file(template_path, Map.to_list(a))
      File.write!(dest, content)
      Mix.shell().info([:green, "* create ", :reset, dest])

      if dest_rel in executable_templates, do: File.chmod!(dest, 0o755)
    end)

    # Copy static files (gradlew, wrapper jars, iOS assets, etc.)
    s_root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&File.dir?/1)
    |> Enum.filter(&platform_included?(&1, s_root, no_ios, no_android))
    |> Enum.reject(&liveview_phoenix_owned?(&1, s_root, opts))
    |> Enum.each(fn src ->
      rel = Path.relative_to(src, s_root)
      dest = Path.join(project_dir, rel)
      File.mkdir_p!(Path.dirname(dest))
      File.copy!(src, dest)
      if rel in executable_static, do: File.chmod!(dest, 0o755)
    end)

    :ok
  end

  # One-time log so the user knows their --local is doing what they
  # expect. The first time templates resolve from a local checkout
  # (rather than the installed archive), say so.
  defp log_local_priv_once(opts, t_root) do
    if Keyword.get(opts, :local, false) do
      archive_root = :code.priv_dir(:mob_new) |> to_string() |> Path.join("templates/mob.new")

      if t_root != archive_root do
        Mix.shell().info([:cyan, "* --local: using templates from ", :reset, t_root])
      end
    end
  end

  @doc """
  When generating a LiveView project, `mix phx.new` already produced its own
  mix.exs, config/, lib/<app>/, lib/<app>_web/, .gitignore, and assets/ — and
  those are the *correct* versions for a Phoenix app (with gettext,
  telemetry_metrics, etc.). The native template's same-named files are
  written for the bare-Mob path and would clobber Phoenix's, leaving the
  project unable to compile.

  When `:liveview` is true in opts, this predicate returns true for any
  template path that Phoenix already owns, so the copy step skips it. Files
  that are unique to Mob (mob.exs, src/<app>.erl, android/, ios/) still get
  emitted normally.

  Public for testing — guards against the regression where a new template
  path lands in the native tree without being added to the LiveView
  blocklist.
  """
  @spec liveview_phoenix_owned?(String.t(), String.t(), keyword()) :: boolean()
  def liveview_phoenix_owned?(path, root, opts) do
    if Keyword.get(opts, :liveview, false) do
      rel = Path.relative_to(path, root)

      cond do
        rel == "mix.exs.eex" -> true
        rel == ".gitignore.eex" -> true
        rel == ".tool-versions.eex" -> true
        String.starts_with?(rel, "config/") -> true
        # Native-template `lib/app_name/` includes sample screens (audio, camera,
        # webview, etc.) that are Mob-native UI — they don't make sense in a
        # LiveView project where the UI is HTML/HEEx, and they collide with
        # Phoenix's own lib/<app>/ contents. Skip the whole subtree; the
        # LiveView-specific MobScreen file is generated by apply_liveview_patches.
        String.starts_with?(rel, "lib/app_name/") -> true
        # priv/repo/migrations is added explicitly by apply_liveview_patches when
        # ecto_sqlite3 is wired up — skip the native template's version.
        String.starts_with?(rel, "priv/") -> true
        true -> false
      end
    else
      false
    end
  end

  # Decide whether a template/static file should be emitted given the platform
  # exclusion flags. Files outside android/ and ios/ are always included
  # (lib/, mix.exs, etc.). Files under android/ are excluded when no_android,
  # likewise ios/ when no_ios.
  defp platform_included?(path, root, no_ios, no_android) do
    rel = Path.relative_to(path, root)

    cond do
      String.starts_with?(rel, "android/") -> not no_android
      String.starts_with?(rel, "ios/") -> not no_ios
      true -> true
    end
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

    # 7b. Patch Phoenix's config files to use 4200 (dev) and 4202 (test) so
    #     `mix phx.server` doesn't collide with another LV project on 4000.
    #     The on-device runtime in mob_app.ex already uses 4200 — this lines
    #     up the host-side dev/test endpoints with that.
    patch_config_ports(project_dir)

    # 8. Write .gitignore entry for mob.exs (append if file exists)
    patch_gitignore(project_dir)

    # 9. Generate the notes starter app: Repo, Note schema, Notes context,
    #    migration, three LiveViews, and patch router + application.ex + configs.
    inject_ecto_sqlite3_dep(project_dir)
    patch_config_for_ecto(project_dir, app_name, module_name)
    generate_notes_app(project_dir, app_name, module_name)

    # 10. (Phase 2 iter 13b) LiveView's ios/build.sh used to be overwritten
    #     here with crypto-shim/ssl-copy/Phoenix-asset glue. All of that
    #     now lives in mob_dev's NativeBuild as `maybe_install_crypto_shim`,
    #     `maybe_copy_ssl_beams`, `maybe_build_phoenix_assets` — gated on
    #     `liveview_project?/0` (presence of phoenix_live_view dep). No
    #     ios/build.sh emission needed; the iOS sim build.zig handles
    #     native compile + link the same way for vanilla and LV.
    _ = {project_dir, app_name, module_name}

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
      Mix.shell().info([
        :yellow,
        "* skip ",
        :reset,
        "assets/js/app.js not found — add MobHook manually"
      ])
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
      Mix.shell().info([
        :yellow,
        "* skip root.html.heex not found — add mob-bridge element manually:",
        :reset
      ])

      Mix.shell().info("    " <> MobNew.LiveViewPatcher.mob_bridge_element())
    end
  end

  defp generate_mob_screen(project_dir, app_name, module_name) do
    dir = Path.join([project_dir, "lib", app_name])
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
    dir = Path.join([project_dir, "lib", app_name])
    path = Path.join(dir, "mob_app.ex")
    File.mkdir_p!(dir)
    # Extract the secret_key_base phx.new wrote into config/dev.exs so that
    # on-device Application.put_env uses the same key the dev server uses.
    # Falls back to a freshly generated key if extraction fails.
    secret_key_base = extract_secret_key_base(project_dir) || generate_secret_key_base()
    signing_salt = generate_signing_salt()

    content =
      MobNew.LiveViewPatcher.mob_live_app_content(
        module_name,
        app_name,
        secret_key_base,
        signing_salt
      )

    File.write!(path, content)
    Mix.shell().info([:green, "* create ", :reset, path])
  end

  defp inject_ecto_sqlite3_dep(project_dir) do
    path = Path.join(project_dir, "mix.exs")

    if File.exists?(path) do
      content = File.read!(path)

      unless String.contains?(content, "ecto_sqlite3") do
        patched =
          Regex.replace(
            Regex.compile!("(defp deps do\\s*\\[)"),
            content,
            ~s[\\1\n      {:ecto_sqlite3, "~> 0.18"},],
            global: false
          )

        File.write!(path, patched)
        Mix.shell().info([:green, "* patch ", :reset, path, " (added ecto_sqlite3)"])
      end
    end
  end

  # phx.new emits Endpoint http port 4000 in dev.exs, 4002 in test.exs, and a
  # `PORT` env var defaulting to "4000" in runtime.exs. Mob's LiveView mode
  # standardises on 4200 (host dev + on-device runtime — see mob_app.ex), so
  # `mix phx.server` from a generated project doesn't collide with someone
  # else's Phoenix app already on 4000. Idempotent: skips the rewrite if the
  # file's port has already been bumped.
  defp patch_config_ports(project_dir) do
    [
      {"config/dev.exs", Regex.compile!("port:\\s*4000\\b"), "port: 4200",
       "dev port 4000 → 4200"},
      {"config/test.exs", Regex.compile!("port:\\s*4002\\b"), "port: 4202",
       "test port 4002 → 4202"},
      # Phoenix ≤ 1.7: `System.get_env("PORT") || "4000"`.
      {"config/runtime.exs", Regex.compile!(~S{"PORT"\s*\)\s*\|\|\s*"4000"}),
       "\"PORT\") || \"4200\"", "runtime PORT default 4000 → 4200 (legacy ||)"},
      # Phoenix ≥ 1.8: `System.get_env("PORT", "4000")` — two-arg form.
      {"config/runtime.exs", Regex.compile!(~S{"PORT"\s*,\s*"4000"}), "\"PORT\", \"4200\"",
       "runtime PORT default 4000 → 4200"}
    ]
    |> Enum.each(&apply_port_patch(project_dir, &1))

    # Fallback for newer Phoenix versions that omit an explicit `port:` line
    # in config/dev.exs (Phoenix defaults the port to 4000 implicitly). The
    # regex above finds nothing to replace, so we have to inject a port: line
    # into the http: keyword list ourselves. Idempotent.
    ensure_dev_port(project_dir)
  end

  defp ensure_dev_port(project_dir) do
    path = Path.join([project_dir, "config", "dev.exs"])

    with true <- File.exists?(path),
         content <- File.read!(path),
         # Idempotency check tied to the actual target value, not a generic
         # `port:\s*\d+` regex — Phoenix's dev.exs ships an SSL example block
         # in comments that contains `port: 4001`, which would otherwise
         # fool a presence-only check into thinking we already patched.
         false <- String.contains?(content, "port: 4200"),
         # First `http: [` in the file is the Endpoint's. Inject the port
         # at the front of its keyword list. The global: false on
         # String.replace ensures only the first occurrence is touched.
         [match | _] <- Regex.run(~r/http:\s*\[/, content) do
      patched = String.replace(content, match, "#{match}port: 4200, ", global: false)
      File.write!(path, patched)
      Mix.shell().info([:green, "* patch ", :reset, path, " (dev port injected → 4200)"])
    else
      _ -> :ok
    end
  end

  defp apply_port_patch(project_dir, {rel, find, replace, label}) do
    path = Path.join(project_dir, rel)

    if File.exists?(path) do
      content = File.read!(path)
      patched = Regex.replace(find, content, replace, global: false)

      if patched != content do
        File.write!(path, patched)
        Mix.shell().info([:green, "* patch ", :reset, path, " (#{label})"])
      end
    end
  end

  defp patch_config_for_ecto(project_dir, app_name, module_name) do
    config_exs = Path.join([project_dir, "config", "config.exs"])
    dev_exs = Path.join([project_dir, "config", "dev.exs"])

    if File.exists?(config_exs) do
      content = File.read!(config_exs)

      unless String.contains?(content, "ecto_repos") do
        ecto_config = """

        config :#{app_name},
          ecto_repos: [#{module_name}.Repo],
          generators: [timestamp_type: :utc_datetime]
        """

        patched =
          String.replace(content, "import_config", ecto_config <> "\nimport_config",
            global: false
          )

        File.write!(config_exs, patched)
        Mix.shell().info([:green, "* patch ", :reset, config_exs, " (added ecto_repos)"])
      end
    end

    if File.exists?(dev_exs) do
      content = File.read!(dev_exs)

      unless String.contains?(content, "#{module_name}.Repo") do
        repo_config = """

        config :#{app_name}, #{module_name}.Repo,
          database: Path.expand("../priv/repo/#{app_name}_dev.db", __DIR__),
          pool_size: 5
        """

        File.write!(dev_exs, content <> repo_config)
        Mix.shell().info([:green, "* patch ", :reset, dev_exs, " (added Repo dev config)"])
      end
    end
  end

  defp generate_notes_app(project_dir, app_name, module_name) do
    live_dir = Path.join([project_dir, "lib", "#{app_name}_web", "live"])
    lib_dir = Path.join([project_dir, "lib", app_name])
    migrations_dir = Path.join([project_dir, "priv", "repo", "migrations"])
    File.mkdir_p!(live_dir)
    File.mkdir_p!(lib_dir)
    File.mkdir_p!(migrations_dir)

    write = fn path, content ->
      File.write!(path, content)
      Mix.shell().info([:green, "* create ", :reset, path])
    end

    write.(
      Path.join(lib_dir, "repo.ex"),
      MobNew.LiveViewPatcher.repo_content(module_name, app_name)
    )

    write.(
      Path.join(lib_dir, "note.ex"),
      MobNew.LiveViewPatcher.note_content(module_name)
    )

    write.(
      Path.join(lib_dir, "notes.ex"),
      MobNew.LiveViewPatcher.notes_content(module_name, app_name)
    )

    write.(
      Path.join(migrations_dir, "20260424000000_create_notes.exs"),
      MobNew.LiveViewPatcher.migration_content(app_name)
    )

    write.(
      Path.join(live_dir, "notes_list_live.ex"),
      MobNew.LiveViewPatcher.notes_list_live_content(module_name, app_name)
    )

    write.(
      Path.join(live_dir, "note_editor_live.ex"),
      MobNew.LiveViewPatcher.note_editor_live_content(module_name, app_name)
    )

    write.(
      Path.join(live_dir, "about_live.ex"),
      MobNew.LiveViewPatcher.about_live_content(module_name, app_name)
    )

    patch_router_for_notes(project_dir, app_name, module_name)
    patch_application_ex_for_repo(project_dir, app_name, module_name)
  end

  defp patch_router_for_notes(project_dir, app_name, _module_name) do
    web_name = app_name <> "_web"
    path = Path.join([project_dir, "lib", web_name, "router.ex"])

    notes_routes =
      ~s[live "/", NotesListLive\n    live "/notes/:id", NoteEditorLive\n    live "/about", AboutLive]

    if File.exists?(path) do
      content = File.read!(path)

      patched =
        Regex.replace(
          Regex.compile!("get\\s+\"\\/\",\\s+PageController,\\s+:home"),
          content,
          notes_routes,
          global: false
        )

      patched =
        if patched == content do
          # Fallback: replace any existing live "/" route
          Regex.replace(
            Regex.compile!("live\\s+\"\\/\",\\s+\\w+"),
            content,
            notes_routes,
            global: false
          )
        else
          patched
        end

      if patched != content do
        File.write!(path, patched)
        Mix.shell().info([:green, "* patch ", :reset, path, " (notes routes)"])
      end
    end
  end

  defp patch_application_ex_for_repo(project_dir, app_name, module_name) do
    path = Path.join([project_dir, "lib", app_name, "application.ex"])

    if File.exists?(path) do
      content = File.read!(path)

      unless String.contains?(content, "#{module_name}.Repo") do
        patched =
          String.replace(
            content,
            "#{module_name}Web.Endpoint",
            "#{module_name}.Repo,\n      #{module_name}Web.Endpoint",
            global: false
          )

        File.write!(path, patched)
        Mix.shell().info([:green, "* patch ", :reset, path, " (added Repo to supervision tree)"])
      end
    end
  end

  @doc false
  @spec extract_secret_key_base(String.t()) :: String.t() | nil
  def extract_secret_key_base(project_dir) do
    dev_exs = Path.join([project_dir, "config", "dev.exs"])

    if File.exists?(dev_exs) do
      content = File.read!(dev_exs)

      case Regex.run(Regex.compile!("secret_key_base:\\s*\"([^\"]{40,})\""), content) do
        [_, key] -> key
        _ -> nil
      end
    end
  end

  @doc false
  @spec generate_secret_key_base() :: String.t()
  def generate_secret_key_base do
    :crypto.strong_rand_bytes(48) |> Base.encode64(padding: false)
  end

  @doc false
  @spec generate_signing_salt() :: String.t()
  def generate_signing_salt do
    :crypto.strong_rand_bytes(8) |> Base.encode64(padding: false)
  end

  defp generate_erlang_entry(project_dir, app_name, module_name) do
    dir = Path.join(project_dir, "src")
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
            Regex.compile!("(def project do\\s*\\[)"),
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

  @doc false
  @spec resolve_deps(keyword()) :: {String.t(), String.t(), String.t(), String.t()}
  def resolve_deps(opts) do
    if opts[:local] do
      mob_dir = resolve_local_path("MOB_DIR", "mob")
      mob_dev_dir = resolve_local_path("MOB_DEV_DIR", "mob_dev")
      elixir_lib = :code.lib_dir(:elixir) |> to_string() |> Path.dirname() |> Path.expand()

      mob_dep = ~s({:mob,     path: "#{mob_dir}"})
      mob_dev_dep = ~s({:mob_dev, path: "#{mob_dev_dir}", only: :dev, runtime: false})
      mob_exs_mob_dir = inspect(mob_dir)
      mob_exs_elixir_lib = inspect(elixir_lib)

      {mob_dep, mob_dev_dep, mob_exs_mob_dir, mob_exs_elixir_lib}
    else
      mob_dep = ~s({:mob,     "~> 0.5"})
      mob_dev_dep = ~s({:mob_dev, "~> 0.3", only: :dev, runtime: false})
      mob_exs_mob_dir = "Path.join(File.cwd!(), \"deps/mob\")"

      # Default to the running Elixir's actual lib dir — `:code.lib_dir(:elixir)`
      # returns ".../lib/elixir", so `Path.dirname/1` yields the parent that
      # holds elixir/, logger/, eex/, etc. that build.sh's stdlib copy needs.
      # A hardcoded version path here drifts the moment the user's mise
      # install moves; a build.sh that copies from an old Elixir into a tarball
      # whose OTP is much newer breaks Phoenix's Regex layer
      # (Elixir.Regex.safe_run/3 function_clause on the on-device re_pattern).
      mob_exs_elixir_lib =
        "System.get_env(\"MOB_ELIXIR_LIB\", :code.lib_dir(:elixir) |> to_string() |> Path.dirname())"

      {mob_dep, mob_dev_dep, mob_exs_mob_dir, mob_exs_elixir_lib}
    end
  end

  @doc false
  @spec resolve_local_path(String.t(), String.t()) :: String.t()
  def resolve_local_path(env_var, sibling_name) do
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

  # iOS sim build.sh.eex eliminated in Phase 2 iter 13b. The
  # generate/4 path (used by `mix mob.new`) keeps a local
  # `executable_templates` list because that one occasionally needs
  # a chmod after rendering — see line ~508. THIS path
  # (`generate/3`, the non-LiveView default + library callers) has
  # no executable templates today. Re-add a chmod hook here only
  # when a template needs it; the `@executable_files []` module
  # attribute that used to live here was triggering Elixir 1.20's
  # type checker on a known-always-false `in` check.

  defp render_templates(assigns, project_dir, opts) do
    no_ios = Keyword.get(opts, :no_ios, false)
    no_android = Keyword.get(opts, :no_android, false)
    t_root = templates_root(opts)
    log_local_priv_once(opts, t_root)

    t_root
    |> find_templates()
    |> Enum.filter(&platform_included?(&1, t_root, no_ios, no_android))
    |> Enum.each(fn template_path ->
      rel = Path.relative_to(template_path, t_root)
      dest_rel = expand_path(rel, assigns)
      dest = Path.join(project_dir, dest_rel)
      File.mkdir_p!(Path.dirname(dest))
      content = EEx.eval_file(template_path, Map.to_list(assigns))
      File.write!(dest, content)
    end)
  end

  defp find_templates(dir) do
    Path.wildcard(Path.join(dir, "**/*.eex"), match_dot: true)
  end

  @executable_static ["android/gradlew"]

  defp copy_static(project_dir, opts) do
    no_ios = Keyword.get(opts, :no_ios, false)
    no_android = Keyword.get(opts, :no_android, false)
    s_root = static_root(opts)

    s_root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&File.dir?/1)
    |> Enum.filter(&platform_included?(&1, s_root, no_ios, no_android))
    |> Enum.each(fn src ->
      rel = Path.relative_to(src, s_root)
      dest = Path.join(project_dir, rel)
      File.mkdir_p!(Path.dirname(dest))
      File.copy!(src, dest)
      if rel in @executable_static, do: File.chmod!(dest, 0o755)
    end)
  end

  @doc false
  # Replace `app_name` placeholder in directory segments and strip .eex extension.
  @spec expand_path(String.t(), map()) :: String.t()
  def expand_path(rel, assigns) do
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
