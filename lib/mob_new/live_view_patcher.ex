defmodule MobNew.LiveViewPatcher do
  @moduledoc """
  Pure helpers for applying the Mob LiveView bridge patches to a freshly
  generated Phoenix project.

  These are duplicated from `MobDev.Enable` (which lives in mob_dev, a separate
  package) to keep mob_new self-contained as a Mix archive with no runtime deps
  on mob_dev.

  ## What gets patched

  1. `assets/js/app.js` — `MobHook` definition inserted after the last import,
     and `MobHook` registered in the `LiveSocket` `hooks:` option.
  2. `lib/<app>_web/components/layouts/root.html.heex` — hidden
     `<div id="mob-bridge" phx-hook="MobHook">` inserted after `<body>`.
  3. `lib/<app>/mob_screen.ex` — generated (the `Mob.Screen` that opens the WebView).
  4. `mob.exs` — `liveview_port: 4000` added.
  5. `mix.exs` — mob / mob_dev deps injected into the `deps/0` function.
  6. `lib/<app>/application.ex` — `Mob.App` child started in the supervision tree.
  """

  @mob_hook_js ~S"""
  // MobHook — Mob LiveView bridge. Added by `mix mob.new --liveview`.
  //
  // WHY THIS EXISTS: The native WebView injects window.mob pointing at the NIF
  // bridge (postMessage on iOS, JavascriptInterface on Android). In LiveView
  // mode we want window.mob to route through the LiveView WebSocket instead so
  // handle_event/3 in your LiveView receives JS messages and push_event/3
  // delivers server messages back to JS.
  //
  // This hook replaces window.mob on mount. It requires a DOM element with
  // phx-hook="MobHook" — see root.html.heex. Without that element this hook
  // never runs and messages silently use the native bridge instead.
  const MobHook = {
    mounted() {
      window.mob = {
        // JS → LiveView: arrives as handle_event("mob_message", data, socket)
        send: (data) => this.pushEvent("mob_message", data),
        // LiveView → JS: push_event(socket, "mob_push", data) calls all handlers
        onMessage: (handler) => this.handleEvent("mob_push", handler),
        // No-op in LiveView mode. The native bridge calls this to deliver
        // webview_post_message results, but in LiveView mode server messages
        // arrive via handleEvent("mob_push") instead.
        _dispatch: () => {}
      }
    }
  }
  """

  @mob_bridge_element ~s(<div id="mob-bridge" phx-hook="MobHook" style="display:none"></div>)

  # ── Public API ────────────────────────────────────────────────────────────────

  @doc "Returns the hidden bridge element string (for test assertions)."
  def mob_bridge_element, do: @mob_bridge_element

  @doc """
  Injects the MobHook definition and registration into the given `app.js` content.

  Idempotent: returns unchanged content if MobHook is already present.
  """
  def inject_mob_hook(content) do
    if String.contains?(content, "MobHook") do
      content
    else
      content
      |> insert_hook_definition()
      |> register_hook_in_live_socket()
    end
  end

  @doc """
  Injects the hidden bridge `<div>` immediately after the opening `<body>` tag.

  Idempotent: returns unchanged content if mob-bridge is already present.
  """
  def inject_mob_bridge_element(content) do
    if String.contains?(content, "mob-bridge") do
      content
    else
      Regex.replace(
        Regex.compile!("<body([^>]*)>"),
        content,
        "<body\\1>\n    #{@mob_bridge_element}",
        global: false
      )
    end
  end

  @doc """
  Injects mob / mob_dev dependencies into the `deps/0` function in `mix.exs` content.

  `mob_dep` and `mob_dev_dep` are the dependency tuple strings (already formatted).
  Idempotent: no-op if `:mob` is already present.
  """
  def inject_deps(content, mob_dep, mob_dev_dep) do
    if String.contains?(content, ":mob,") or String.contains?(content, ":mob ") do
      content
    else
      # Insert before the closing bracket of the deps list
      String.replace(
        content,
        Regex.compile!("(defp deps do\\s*\\[)"),
        "\\1\n      #{mob_dep},\n      #{mob_dev_dep},",
        global: false
      )
    end
  end

  @doc """
  Generates the MobScreen source file content for the given module name.
  """
  def mob_screen_content(module_name) do
    """
    defmodule #{module_name}.MobScreen do
      @moduledoc \"\"\"
      Mob.Screen that wraps the Phoenix LiveView app in a native WebView.

      This screen is started automatically alongside the Phoenix endpoint.
      You can push events from your LiveViews to JS with:

          push_event(socket, "mob_push", %{type: "my_event", data: ...})

      And receive JS events in your LiveViews with:

          def handle_event("mob_message", data, socket) do
            ...
          end
      \"\"\"
      use Mob.Screen

      def mount(_params, _session, socket) do
        {:ok, socket}
      end

      def render(_assigns) do
        Mob.UI.webview(
          url: Mob.LiveView.local_url("/"),
          show_url: false
        )
      end
    end
    """
  end

  @doc """
  Generates mob.exs config content for a LiveView project.
  """
  def mob_exs_content(mob_exs_mob_dir, mob_exs_elixir_lib) do
    """
    # mob.exs — Mob build environment configuration.
    # Set these paths for your machine. Not committed to version control.
    # (Add mob.exs to .gitignore if you share this project.)
    #
    # OTP runtimes for Android and iOS are downloaded automatically by `mix mob.install`.

    import Config

    config :mob_dev,
      # Path to the mob library repo (native source files for iOS/Android builds).
      mob_dir: #{mob_exs_mob_dir},

      # Path to your Elixir lib dir (e.g. ~/.local/share/mise/installs/elixir/1.18.4-otp-28/lib).
      elixir_lib: #{mob_exs_elixir_lib}

    config :mob, liveview_port: 4200
    """
  end

  @doc """
  Generates the `mob_app.ex` entry point for a LiveView project.

  This module is called from the Erlang bootstrap (`src/app_name.erl`) instead
  of a native `Mob.App` module. It starts the Phoenix OTP application (which
  boots the endpoint) and then starts `MobScreen` to open the WebView.

  Unlike native Mob apps, this does NOT `use Mob.App` — Phoenix owns the
  supervision tree. Mob is wired in at the BEAM entry level only.

  `secret_key_base` and `signing_salt` are embedded directly because Mix config
  files (`config/*.exs`) are not loaded on-device — `Application.put_env/3` is
  the only way to configure the endpoint before `ensure_all_started/1` runs.
  Port 4200 avoids conflicts with a host `mix phx.server` on 4000.
  """
  def mob_live_app_content(module_name, app_name, secret_key_base, signing_salt) do
    """
    defmodule #{module_name}.MobApp do
      @moduledoc \"\"\"
      BEAM entry point for the LiveView Mob app.

      Called from `src/#{app_name}.erl` by the iOS/Android native launcher.
      Starts the Phoenix OTP application (which boots the endpoint and all
      supervision trees), then opens the MobScreen WebView pointing at
      http://127.0.0.1:<liveview_port>/ (port set in mob.exs).

      This module is the LiveView equivalent of `Mob.App`. It does not use
      `use Mob.App` because Phoenix owns the supervision tree. Mob is added
      only as a WebView wrapper around the running Phoenix endpoint.
      \"\"\"

      def start do
        Mob.NativeLogger.install()

        # On-device, Mix config files are not loaded — set Phoenix endpoint
        # config explicitly before starting applications so the endpoint knows
        # its port, adapter, and secret key base. Watchers and code reload
        # are omitted (no dev tools on-device).
        #
        # Port 4200 avoids conflicts with a host `mix phx.server` on 4000
        # (iOS simulator shares the host loopback at 127.0.0.1).
        liveview_port = Application.get_env(:mob, :liveview_port, 4200)
        Application.put_env(:mob, :liveview_port, liveview_port)
        Application.put_env(:#{app_name}, #{module_name}Web.Endpoint,
          adapter: Bandit.PhoenixAdapter,
          http: [ip: {127, 0, 0, 1}, port: liveview_port],
          check_origin: false,
          debug_errors: true,
          server: true,
          secret_key_base: "#{secret_key_base}",
          pubsub_server: #{module_name}.PubSub,
          live_view: [signing_salt: "#{signing_salt}"]
        )

        # ecto_sqlite3 must be started before #{app_name} so its NIF is loaded
        # before the Repo supervisor tries to open the database.
        {:ok, _} = Application.ensure_all_started(:ecto_sqlite3)

        # Start the Phoenix application and all its children.
        # This boots the endpoint, repo, pubsub, telemetry, etc.
        {:ok, _} = Application.ensure_all_started(:#{app_name})

        # Run any pending Ecto migrations. MOB_BEAMS_DIR is set by the native
        # launcher to the flat deploy directory; migrations are copied there at
        # build time. Falls back to Application.app_dir when running in dev.
        Ecto.Migrator.with_repo(#{module_name}.Repo, fn _repo ->
          Ecto.Migrator.run(#{module_name}.Repo, migrations_dir(), :up, all: true)
        end)

        # ComponentRegistry is normally started by Mob.App but we bypass that.
        # Start it standalone so Mob.Screen.start_root can render components.
        {:ok, _} = Mob.ComponentRegistry.start_link()

        # Start the MobScreen WebView pointing at the local Phoenix endpoint.
        # The WebView loads http://127.0.0.1:<liveview_port>/ (see mob.exs).
        Mob.Screen.start_root(#{module_name}.MobScreen)

        # Start Erlang distribution so `mix mob.connect` can attach.
        Mob.Dist.ensure_started(node: :"#{app_name}_android@127.0.0.1", cookie: :mob_secret)
      end

      defp migrations_dir do
        case System.get_env("MOB_BEAMS_DIR") do
          nil -> Application.app_dir(:#{app_name}, "priv/repo/migrations")
          beams_dir -> Path.join([beams_dir, "priv", "repo", "migrations"])
        end
      end
    end
    """
  end

  @doc """
  Generates `lib/<app>_web/live/page_live.ex` — a minimal starter LiveView
  that replaces the default PageController route.
  """
  def page_live_content(module_name, app_name) do
    """
    defmodule #{module_name}Web.PageLive do
      use #{module_name}Web, :live_view

      def mount(_params, _session, socket) do
        {:ok, assign(socket, :pong, false)}
      end

      def render(assigns) do
        ~H\"\"\"
        <div class="p-8">
          <h1 class="text-2xl font-bold text-zinc-900">#{module_name} on Mob</h1>
          <p class="mt-4 text-zinc-600">
            LiveView is running on-device! Edit
            <code class="text-sm bg-zinc-100 px-1 rounded">lib/#{app_name}_web/live/page_live.ex</code>
            to get started.
          </p>
          <button
            phx-click="ping"
            class="mt-6 px-4 py-2 bg-indigo-600 text-white rounded-lg text-sm font-medium hover:bg-indigo-700"
          >
            Ping
          </button>
          <p :if={@pong} class="mt-4 text-green-600 font-semibold">Pong!</p>
        </div>
        \"\"\"
      end

      def handle_event("ping", _params, socket) do
        {:noreply, assign(socket, :pong, true)}
      end
    end
    """
  end

  @doc "Generates `lib/<app>/repo.ex` — Ecto.Repo backed by SQLite3."
  def repo_content(module_name, app_name) do
    """
    defmodule #{module_name}.Repo do
      use Ecto.Repo,
        otp_app: :#{app_name},
        adapter: Ecto.Adapters.SQLite3

      @impl true
      def init(_type, config) do
        db_path =
          case System.get_env("MOB_DATA_DIR") do
            nil -> config[:database] || Path.join(File.cwd!(), "#{app_name}.db")
            dir -> Path.join(dir, "app.db")
          end

        {:ok, Keyword.merge(config, database: db_path, pool_size: 1)}
      end
    end
    """
  end

  @doc "Generates `lib/<app>/note.ex` — the Note Ecto schema."
  def note_content(module_name) do
    """
    defmodule #{module_name}.Note do
      use Ecto.Schema
      import Ecto.Changeset

      schema "notes" do
        field :title, :string, default: ""
        field :body, :string, default: ""
        timestamps(type: :utc_datetime)
      end

      def changeset(note, attrs) do
        note
        |> cast(attrs, [:title, :body])
      end
    end
    """
  end

  @doc "Generates `lib/<app>/notes.ex` — the Notes context with seed data."
  def notes_content(module_name, _app_name) do
    """
    defmodule #{module_name}.Notes do
      import Ecto.Query
      alias #{module_name}.{Repo, Note}

      @seeds [
        %{title: "Welcome to Mob", body: "LiveView is running on-device inside a WKWebView. The full Phoenix stack — Bandit, Plug, LiveView WebSocket — runs entirely on the device.\\n\\nTry editing this note!"},
        %{title: "How it works", body: "The app boots the BEAM, starts the Phoenix endpoint on 127.0.0.1:4200, then loads http://127.0.0.1:4200/ in a native WebView.\\n\\nLiveView handles all UI updates over a WebSocket — no page reloads needed."},
        %{title: "Things to try", body: "• Create a new note with the + button\\n• Edit any note — changes persist to SQLite\\n• Delete notes by tapping the × button\\n• Check out the About tab"},
      ]

      def list do
        Repo.all(from n in Note, order_by: [desc: n.updated_at])
        |> maybe_seed()
      end

      def get(id), do: Repo.get(Note, id)

      def create do
        %Note{}
        |> Note.changeset(%{title: "", body: ""})
        |> Repo.insert!()
      end

      def update(id, attrs) do
        case Repo.get(Note, id) do
          nil -> nil
          note ->
            note
            |> Note.changeset(attrs)
            |> Repo.update!()
        end
      end

      def delete(id) do
        case Repo.get(Note, id) do
          nil -> :ok
          note -> Repo.delete!(note)
        end
        :ok
      end

      defp maybe_seed([]) do
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        @seeds
        |> Enum.with_index()
        |> Enum.each(fn {attrs, i} ->
          ts = DateTime.add(now, -i * 3600, :second)
          Repo.insert!(%Note{title: attrs.title, body: attrs.body, inserted_at: ts, updated_at: ts})
        end)
        Repo.all(from n in Note, order_by: [desc: n.updated_at])
      end
      defp maybe_seed(notes), do: notes
    end
    """
  end

  @doc "Generates the create_notes Ecto migration."
  def migration_content(app_name) do
    module = app_name |> Macro.camelize()

    """
    defmodule #{module}.Repo.Migrations.CreateNotes do
      use Ecto.Migration

      def change do
        create table(:notes) do
          add :title, :string, default: ""
          add :body, :text, default: ""
          timestamps(type: :utc_datetime)
        end
      end
    end
    """
  end

  @doc "Generates `lib/<app>_web/live/notes_list_live.ex`."
  def notes_list_live_content(module_name, _app_name) do
    """
    defmodule #{module_name}Web.NotesListLive do
      use #{module_name}Web, :live_view

      alias #{module_name}.Notes

      def mount(_params, _session, socket) do
        {:ok, assign(socket, notes: Notes.list(), page_title: "Notes")}
      end

      def render(assigns) do
        ~H\"\"\"
        <div class="px-4 pt-4">
          <div class="flex items-center justify-between mb-4">
            <h1 class="text-2xl font-bold text-gray-900">Notes</h1>
            <button
              phx-click="new_note"
              class="w-10 h-10 flex items-center justify-center bg-indigo-600 text-white rounded-full shadow-md text-2xl leading-none"
              aria-label="New note"
            >
              +
            </button>
          </div>

          <ul :if={@notes != []} class="space-y-2">
            <li :for={note <- @notes}>
              <div class="flex items-stretch bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
                <button
                  phx-click="open"
                  phx-value-id={note.id}
                  class="flex-1 text-left px-4 py-3 min-h-[72px]"
                >
                  <p class="font-semibold text-gray-900 leading-tight truncate">
                    {if note.title == "", do: "Untitled", else: note.title}
                  </p>
                  <p class="text-sm text-gray-500 mt-0.5 line-clamp-2">
                    {if note.body == "", do: "No content", else: note.body}
                  </p>
                  <p class="text-xs text-gray-400 mt-1">{format_time(note.updated_at)}</p>
                </button>
                <button
                  phx-click="delete"
                  phx-value-id={note.id}
                  data-confirm="Delete this note?"
                  class="px-4 text-gray-300 hover:text-red-400 border-l border-gray-100 text-xl"
                  aria-label="Delete"
                >
                  ×
                </button>
              </div>
            </li>
          </ul>

          <div :if={@notes == []} class="flex flex-col items-center justify-center mt-24 text-center">
            <p class="text-5xl mb-4">📝</p>
            <p class="text-gray-500 text-lg font-medium">No notes yet</p>
            <p class="text-gray-400 text-sm mt-1">Tap + to create your first note</p>
          </div>
        </div>
        \"\"\"
      end

      def handle_event("new_note", _params, socket) do
        note = Notes.create()
        {:noreply, push_navigate(socket, to: "/notes/\#{note.id}")}
      end

      def handle_event("open", %{"id" => id}, socket) do
        {:noreply, push_navigate(socket, to: "/notes/\#{id}")}
      end

      def handle_event("delete", %{"id" => id}, socket) do
        Notes.delete(id)
        {:noreply, assign(socket, notes: Notes.list())}
      end

      defp format_time(dt) do
        now = DateTime.utc_now()
        diff = DateTime.diff(now, dt, :second)

        cond do
          diff < 60 -> "Just now"
          diff < 3600 -> "\#{div(diff, 60)}m ago"
          diff < 86_400 -> "\#{div(diff, 3600)}h ago"
          true -> Calendar.strftime(dt, "%b %-d")
        end
      end
    end
    """
  end

  @doc "Generates `lib/<app>_web/live/note_editor_live.ex`."
  def note_editor_live_content(module_name, _app_name) do
    """
    defmodule #{module_name}Web.NoteEditorLive do
      use #{module_name}Web, :live_view

      alias #{module_name}.Notes

      def mount(%{"id" => id}, _session, socket) do
        case Notes.get(id) do
          nil ->
            {:ok, push_navigate(socket, to: "/")}

          note ->
            {:ok,
             assign(socket,
               note: note,
               word_count: count_words(note.body),
               saved: true,
               page_title: if(note.title == "", do: "New Note", else: note.title)
             )}
        end
      end

      def render(assigns) do
        ~H\"\"\"
        <div class="flex flex-col h-screen bg-white">
          <div class="flex items-center px-4 pt-4 pb-2 border-b border-gray-100">
            <a
              href="/"
              class="flex items-center text-indigo-600 text-sm font-medium mr-4 min-w-[44px] min-h-[44px] -ml-2 px-2 justify-center"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5 8.25 12l7.5-7.5" />
              </svg>
              Notes
            </a>
            <span class="ml-auto text-xs text-gray-400">
              {if @saved, do: "Saved", else: "Saving…"}
            </span>
          </div>

          <form phx-change="update_note" class="flex-1 flex flex-col overflow-hidden">
            <input
              type="text"
              name="title"
              value={@note.title}
              placeholder="Title"
              class="w-full px-4 pt-4 pb-2 text-2xl font-bold text-gray-900 placeholder-gray-300 border-none outline-none bg-white"
            />

            <textarea
              name="body"
              placeholder="Start writing…"
              class="flex-1 w-full px-4 py-2 text-base text-gray-800 placeholder-gray-300 border-none outline-none resize-none bg-white leading-relaxed"
            >{@note.body}</textarea>
          </form>

          <div class="px-4 py-3 border-t border-gray-100 flex items-center justify-between mb-16">
            <span class="text-xs text-gray-400">
              {@word_count} {if @word_count == 1, do: "word", else: "words"}
            </span>
            <span class="text-xs text-gray-400">
              {String.length(@note.body)} chars
            </span>
          </div>
        </div>
        \"\"\"
      end

      def handle_event("update_note", %{"title" => title, "body" => body}, socket) do
        note = Notes.update(socket.assigns.note.id, %{title: title, body: body})
        {:noreply, assign(socket,
          note: note,
          word_count: count_words(body),
          saved: true,
          page_title: if(title == "", do: "New Note", else: title)
        )}
      end

      defp count_words(""), do: 0
      defp count_words(text) do
        # Regex.compile!/1 (not ~r/...) — a sigil regex gets precompiled
        # into this beam file using a bytecode format that references
        # :re.import/1, which is missing on OTP 28.0 (the version mob's
        # bundled iOS/Android tarballs ship). Compiling at runtime
        # sidesteps that. Once you upgrade off OTP 28.0 you can switch
        # back to ~r/\\s+/.
        text |> String.split(Regex.compile!("\\s+"), trim: true) |> length()
      end
    end
    """
  end

  @doc "Generates `lib/<app>_web/live/about_live.ex`."
  def about_live_content(module_name, _app_name) do
    """
    defmodule #{module_name}Web.AboutLive do
      use #{module_name}Web, :live_view

      def mount(_params, _session, socket) do
        {:ok,
         assign(socket,
           page_title: "About",
           name: "Anonymous",
           editing_name: false,
           name_draft: "Anonymous",
           blurb: "Write something about yourself here.",
           blurb_word_count: 5
         )}
      end

      def render(assigns) do
        ~H\"\"\"
        <div class="px-4 pt-6 max-w-lg mx-auto">
          <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6 mb-4">
            <div class="flex items-center gap-4 mb-4">
              <div class="w-16 h-16 rounded-full bg-indigo-100 flex items-center justify-center text-2xl font-bold text-indigo-600">
                {String.first(@name) |> String.upcase()}
              </div>
              <div class="flex-1 min-w-0">
                <%= if @editing_name do %>
                  <form phx-submit="save_name" class="flex gap-2">
                    <input
                      type="text"
                      name="name"
                      value={@name_draft}
                      phx-change="draft_name"
                      autofocus
                      maxlength="40"
                      class="flex-1 border border-indigo-300 rounded-lg px-3 py-1.5 text-lg font-semibold text-gray-900 outline-none focus:ring-2 focus:ring-indigo-500"
                    />
                    <button
                      type="submit"
                      class="px-3 py-1.5 bg-indigo-600 text-white rounded-lg text-sm font-medium"
                    >
                      Save
                    </button>
                  </form>
                <% else %>
                  <div class="flex items-center gap-2">
                    <p class="text-xl font-bold text-gray-900 truncate">{@name}</p>
                    <button
                      phx-click="edit_name"
                      class="text-gray-400 hover:text-indigo-500 p-1"
                      aria-label="Edit name"
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L6.832 19.82a4.5 4.5 0 0 1-1.897 1.13l-2.685.8.8-2.685a4.5 4.5 0 0 1 1.13-1.897L16.863 4.487Zm0 0L19.5 7.125" />
                      </svg>
                    </button>
                  </div>
                  <p class="text-sm text-gray-400">Tap the pencil to edit</p>
                <% end %>
              </div>
            </div>
          </div>

          <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-5 mb-4">
            <div class="flex items-center justify-between mb-3">
              <h2 class="text-sm font-semibold text-gray-500 uppercase tracking-wide">About me</h2>
              <span class="text-xs text-gray-400">
                {@blurb_word_count} {if @blurb_word_count == 1, do: "word", else: "words"}
              </span>
            </div>
            <textarea
              name="blurb"
              phx-change="update_blurb"
              phx-debounce="200"
              placeholder="Write something about yourself…"
              rows="5"
              class="w-full text-base text-gray-700 placeholder-gray-300 border-none outline-none resize-none leading-relaxed"
            >{@blurb}</textarea>
          </div>

          <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-5">
            <h2 class="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">App info</h2>
            <dl class="space-y-2 text-sm">
              <div class="flex justify-between">
                <dt class="text-gray-500">Framework</dt>
                <dd class="font-medium text-gray-800">Phoenix LiveView</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-gray-500">Runtime</dt>
                <dd class="font-medium text-gray-800">BEAM on device</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-gray-500">Transport</dt>
                <dd class="font-medium text-gray-800">WebSocket</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-gray-500">OTP</dt>
                <dd class="font-medium text-gray-800">{:erlang.system_info(:otp_release)}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-gray-500">Elixir</dt>
                <dd class="font-medium text-gray-800">{System.version()}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-gray-500">Notes stored</dt>
                <dd class="font-medium text-gray-800">{#{module_name}.Notes.list() |> length()}</dd>
              </div>
            </dl>
          </div>
        </div>
        \"\"\"
      end

      def handle_event("edit_name", _params, socket) do
        {:noreply, assign(socket, editing_name: true, name_draft: socket.assigns.name)}
      end

      def handle_event("draft_name", %{"name" => name}, socket) do
        {:noreply, assign(socket, name_draft: name)}
      end

      def handle_event("save_name", %{"name" => name}, socket) do
        name = if String.trim(name) == "", do: "Anonymous", else: String.trim(name)
        {:noreply, assign(socket, name: name, editing_name: false)}
      end

      def handle_event("update_blurb", %{"blurb" => blurb}, socket) do
        # See note in NoteEditorLive.count_words about Regex.compile!/1
        # vs ~r/.../ — OTP 28.0 sigil-regex precompile bug.
        count = blurb |> String.split(Regex.compile!("\\s+"), trim: true) |> length()
        {:noreply, assign(socket, blurb: blurb, blurb_word_count: count)}
      end
    end
    """
  end

  # liveview_build_sh_content/2 was removed in Phase 2 iter 13b. The
  # crypto shim, ssl beam copy, Phoenix asset build, and BEAM glob copy
  # all live in mob_dev's NativeBuild now (gated on liveview_project?/0).

  @doc """
  Generates the Erlang bootstrap for a LiveView project.

  Calls `ModuleName.MobApp.start()` instead of `ModuleName.App.start()`.
  """
  def erlang_entry_content(module_name, app_name) do
    """
    %% #{app_name}.erl — BEAM bootstrap for #{module_name} (LiveView mode).
    %% Called by the iOS/Android native launcher via -eval '#{app_name}:start().'.
    %% Starts the OTP ecosystem, then starts Phoenix + MobScreen via MobApp.
    -module(#{app_name}).
    -export([start/0]).

    start() ->
        step(1, fun() -> application:start(compiler) end),
        step(2, fun() -> application:start(elixir)   end),
        step(3, fun() -> application:start(logger)   end),
        step(4, fun() -> mob_nif:platform()          end),
        step(5, fun() -> 'Elixir.#{module_name}.MobApp':start() end),
        timer:sleep(infinity).

    step(N, Fun) ->
        mob_nif:log("step " ++ integer_to_list(N) ++ " starting"),
        Result = (catch Fun()),
        mob_nif:log("step " ++ integer_to_list(N) ++ " => " ++
                    lists:flatten(io_lib:format("~p", [Result]))).
    """
  end

  # ── Private ───────────────────────────────────────────────────────────────────

  # Insert `hooks: {MobHook}` before the closing `})` of the LiveSocket call.
  # Works by tracking brace depth line by line — avoids regex fights with nested braces.
  defp insert_hooks_before_closing(content) do
    lines = String.split(content, "\n")

    {result_lines, _} =
      Enum.reduce(lines, {[], :before}, fn line, {acc, state} ->
        reduce_line(line, acc, state)
      end)

    Enum.join(result_lines, "\n")
  end

  defp reduce_line(line, acc, :before) do
    if String.contains?(line, "new LiveSocket(") do
      depth = count_brace_depth(line)

      if depth <= 0 do
        patched =
          Regex.replace(Regex.compile!("\\)\\s*$"), line, ", {hooks: {MobHook}})", global: false)

        {acc ++ [patched], :done}
      else
        {acc ++ [line], {:in_call, depth}}
      end
    else
      {acc ++ [line], :before}
    end
  end

  defp reduce_line(line, acc, {:in_call, depth}) do
    new_depth = depth + count_brace_depth(line)
    trimmed = String.trim(line)

    if new_depth <= 0 and (trimmed == "})" or String.starts_with?(trimmed, "})")) do
      {insert_hooks_line(acc, line), :done}
    else
      {acc ++ [line], {:in_call, new_depth}}
    end
  end

  defp reduce_line(line, acc, :done), do: {acc ++ [line], :done}

  defp insert_hooks_line(acc, closing_line) do
    last_acc = List.last(acc)
    last_trimmed = if last_acc, do: String.trim_trailing(last_acc), else: ""

    acc_with_comma =
      if String.ends_with?(last_trimmed, ",") do
        acc
      else
        List.update_at(acc, -1, fn l -> String.trim_trailing(l) <> "," end)
      end

    acc_with_comma ++ ["  hooks: {MobHook}", closing_line]
  end

  # Returns the net brace depth change for a line (opens minus closes).
  defp count_brace_depth(line) do
    opens = line |> String.graphemes() |> Enum.count(&(&1 == "{"))
    closes = line |> String.graphemes() |> Enum.count(&(&1 == "}"))
    opens - closes
  end

  defp insert_hook_definition(content) do
    lines = String.split(content, "\n")

    last_import_idx =
      lines
      |> Enum.with_index()
      |> Enum.filter(fn {line, _} -> String.starts_with?(String.trim(line), "import ") end)
      |> Enum.map(fn {_, idx} -> idx end)
      |> List.last()

    insert_at = (last_import_idx || -1) + 1
    hook_lines = String.split(@mob_hook_js, "\n")

    (Enum.take(lines, insert_at) ++ [""] ++ hook_lines ++ Enum.drop(lines, insert_at))
    |> Enum.join("\n")
  end

  defp register_hook_in_live_socket(content) do
    cond do
      String.contains?(content, "hooks: {}") ->
        String.replace(content, "hooks: {}", "hooks: {MobHook}")

      Regex.match?(Regex.compile!("hooks:\\s*\\{"), content) ->
        # hooks key already exists — prepend MobHook to it
        Regex.replace(
          Regex.compile!("(hooks:\\s*\\{)"),
          content,
          "\\1MobHook, ",
          global: false
        )

      true ->
        # No hooks key. Insert `hooks: {MobHook}` into the LiveSocket options.
        #
        # Strategy: process line by line. Once we see `new LiveSocket(`, track
        # nesting depth. When we find the line that closes the options object
        # (depth goes to 0 with `})`), insert `hooks: {MobHook}` before it.
        #
        # This handles both single-line and multiline LiveSocket calls correctly
        # without fighting nested-brace regex limitations.
        insert_hooks_before_closing(content)
    end
  end
end
