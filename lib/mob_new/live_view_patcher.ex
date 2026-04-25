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
        ~r/<body([^>]*)>/,
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
        ~r/(defp deps do\s*\[)/,
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

        # Start the Phoenix application and all its children.
        # This boots the endpoint, repo, pubsub, telemetry, etc.
        {:ok, _} = Application.ensure_all_started(:#{app_name})

        # ComponentRegistry is normally started by Mob.App but we bypass that.
        # Start it standalone so Mob.Screen.start_root can render components.
        {:ok, _} = Mob.ComponentRegistry.start_link()

        # Start the MobScreen WebView pointing at the local Phoenix endpoint.
        # The WebView loads http://127.0.0.1:<liveview_port>/ (see mob.exs).
        Mob.Screen.start_root(#{module_name}.MobScreen)

        # Start Erlang distribution so `mix mob.connect` can attach.
        Mob.Dist.ensure_started(node: :"#{app_name}_android@127.0.0.1", cookie: :mob_secret)
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

  @doc """
  Generates the LiveView-specific `ios/build.sh` content.

  Key differences from the native build.sh:
  - Copies ALL compiled deps (Phoenix, Plug, Bandit, etc.) with a glob loop
  - Ships a full crypto shim: pbkdf2_hmac/5, exor/2, HMAC-MD5 via erlang:md5/1
  - Copies pure-Erlang ssl beams from host OTP (thousand_island requires :ssl)
  - Builds and deploys JS/CSS assets to BEAMS_DIR/priv/static/ so Plug.Static
    can serve them (code:priv_dir(:app) resolves relative to the flat BEAMS_DIR)
  - No exqlite NIF cross-compile (no Ecto in LiveView projects)
  """
  def liveview_build_sh_content(module_name, app_name) do
    display_name = module_name

    """
    #!/bin/bash
    # ios/build.sh — Build and deploy #{display_name} to iOS simulator (LiveView mode).
    # Reads paths from environment (set by `mix mob.deploy --native` via mob.exs,
    # or export them manually before running this script directly).
    #
    # Required env vars (set in mob.exs or export manually):
    #   MOB_DIR          — path to mob library repo
    #   MOB_ELIXIR_LIB   — path to Elixir lib dir
    #   MOB_IOS_OTP_ROOT — iOS OTP runtime root (set automatically by mob_dev OtpDownloader)
    set -e
    cd "$(dirname "$0")/.."     # project root (contains mix.exs)

    # ── Paths ─────────────────────────────────────────────────────────────────────
    MOB_DIR="${MOB_DIR:?MOB_DIR not set — configure mob.exs}"
    ELIXIR_LIB="${MOB_ELIXIR_LIB:?MOB_ELIXIR_LIB not set — configure mob.exs}"
    OTP_ROOT="${MOB_IOS_OTP_ROOT:?MOB_IOS_OTP_ROOT not set — run mix mob.install to download OTP}"

    # Auto-detect ERTS version from the OTP runtime root.
    ERTS_VSN=$(ls "$OTP_ROOT" | grep '^erts-' | sort -V | tail -1)
    if [ -z "$ERTS_VSN" ]; then
        echo "ERROR: No erts-* directory found in $OTP_ROOT"
        echo "       Have you built OTP for iOS simulator?"
        exit 1
    fi

    BEAMS_DIR="$OTP_ROOT/#{app_name}"
    SDKROOT=$(xcrun -sdk iphonesimulator --show-sdk-path)
    CC="xcrun -sdk iphonesimulator cc -arch arm64 -mios-simulator-version-min=16.0 -isysroot $SDKROOT"

    IFLAGS="-I$OTP_ROOT/$ERTS_VSN/include \\
            -I$OTP_ROOT/$ERTS_VSN/include/aarch64-apple-iossimulator \\
            -I$MOB_DIR/ios"

    LIBS="
      $OTP_ROOT/$ERTS_VSN/lib/libbeam.a
      $OTP_ROOT/$ERTS_VSN/lib/internal/liberts_internal_r.a
      $OTP_ROOT/$ERTS_VSN/lib/internal/libethread.a
      $OTP_ROOT/$ERTS_VSN/lib/libzstd.a
      $OTP_ROOT/$ERTS_VSN/lib/libepcre.a
      $OTP_ROOT/$ERTS_VSN/lib/libryu.a
      $OTP_ROOT/$ERTS_VSN/lib/asn1rt_nif.a
    "

    # ── Find booted simulator ──────────────────────────────────────────────────────
    if [ -n "$1" ]; then
        SIM_ID="$1"
    else
        SIM_ID=$(xcrun simctl list devices booted -j \\
            | python3 -c "
    import json,sys
    d=json.load(sys.stdin)
    for sims in d['devices'].values():
        for s in sims:
            if s.get('state') == 'Booted':
                print(s['udid'])
                exit()
    " 2>/dev/null || true)
    fi

    if [ -z "$SIM_ID" ]; then
        echo "ERROR: No booted simulator found. Boot one in Simulator.app or pass UDID as argument."
        exit 1
    fi
    echo "=== Target simulator: $SIM_ID ==="

    # ── Compile Erlang/Elixir ──────────────────────────────────────────────────────
    echo "=== Compiling Erlang/Elixir ==="
    mix compile

    echo "=== Copying BEAM files to $BEAMS_DIR ==="
    mkdir -p "$BEAMS_DIR"
    # Copy .beam and .app files for ALL compiled deps + the app itself.
    # .app files are required by application:ensure_all_started to resolve OTP metadata.
    # The glob loop handles Phoenix, Plug, Bandit, phoenix_live_view, etc. automatically.
    for lib_dir in _build/dev/lib/*/ebin; do
        cp "$lib_dir"/* "$BEAMS_DIR/" 2>/dev/null || true
    done

    echo "=== Copying Elixir stdlib ==="
    mkdir -p "$OTP_ROOT/lib/elixir/ebin"
    mkdir -p "$OTP_ROOT/lib/logger/ebin"
    cp "$ELIXIR_LIB/elixir/ebin/"*.beam  "$OTP_ROOT/lib/elixir/ebin/"
    cp "$ELIXIR_LIB/elixir/ebin/elixir.app" "$OTP_ROOT/lib/elixir/ebin/"
    cp "$ELIXIR_LIB/logger/ebin/"*.beam  "$OTP_ROOT/lib/logger/ebin/"
    cp "$ELIXIR_LIB/logger/ebin/logger.app" "$OTP_ROOT/lib/logger/ebin/"

    # EEx is used by Phoenix templates — copy into BEAMS_DIR so code:where_is_file("eex.app")
    # resolves correctly alongside other Elixir stdlib beams.
    cp "$ELIXIR_LIB/eex/ebin/"*.beam  "$BEAMS_DIR/"
    cp "$ELIXIR_LIB/eex/ebin/eex.app" "$BEAMS_DIR/"

    echo "=== Installing crypto shim (iOS OTP has no OpenSSL) ==="
    # phoenix and plug_crypto list :crypto as a required OTP application.
    # The iOS OTP build does not include crypto (no OpenSSL NIF).
    # This shim satisfies application:ensure_started(:crypto) so the app boots.
    # For HTTP-only Phoenix at loopback, crypto is never actually called for TLS.
    # pbkdf2_hmac/5 is needed by plug_crypto KeyGenerator (session key derivation).
    # exor/2 is needed by Plug.CSRFProtection (token masking).
    # Both are implemented in pure Erlang using erlang:md5/1 (a built-in BIF).
    CRYPTO_TMP=$(mktemp -d)
    cat > "$CRYPTO_TMP/crypto.erl" << 'ERLEOF'
    -module(crypto).
    -behaviour(application).
    -export([start/2, stop/1, strong_rand_bytes/1, rand_bytes/1,
             hash/2, mac/4, mac/3, supports/1, exor/2,
             generate_key/2, compute_key/4, sign/4, verify/5,
             pbkdf2_hmac/5]).
    start(_Type, _Args) -> {ok, self()}.
    stop(_State) -> ok.
    strong_rand_bytes(N) -> rand:bytes(N).
    rand_bytes(N) -> rand:bytes(N).
    hash(_Type, Data) -> erlang:md5(iolist_to_binary(Data)).
    supports(_Type) -> [].
    generate_key(_Alg, _Params) -> {<<>>, <<>>}.
    compute_key(_Alg, _OtherKey, _MyKey, _Params) -> <<>>.
    sign(_Alg, _DigestType, _Msg, _Key) -> <<>>.
    verify(_Alg, _DigestType, _Msg, _Signature, _Key) -> true.
    %% crypto:exor/2 — used by Plug.CSRFProtection to mask tokens.
    exor(A, B) -> xor_bytes(iolist_to_binary(A), iolist_to_binary(B)).
    %% Pure-Erlang HMAC-MD5 shim. DigestType ignored (local dev only).
    mac(hmac, _HashAlg, Key, Data) ->
        hmac_md5(iolist_to_binary(Key), iolist_to_binary(Data));
    mac(_Type, _SubType, _Key, _Data) -> <<>>.
    mac(_Type, _Key, _Data) -> <<>>.
    %% pbkdf2_hmac/5 — used by plug_crypto KeyGenerator for session key derivation.
    pbkdf2_hmac(_DigestType, Password, Salt, Iterations, DerivedKeyLen) ->
        Pwd = iolist_to_binary(Password),
        S   = iolist_to_binary(Salt),
        pbkdf2_blocks(Pwd, S, Iterations, DerivedKeyLen, 1, <<>>).
    pbkdf2_blocks(_Pwd, _Salt, _Iter, Len, _Block, Acc) when byte_size(Acc) >= Len ->
        binary:part(Acc, 0, Len);
    pbkdf2_blocks(Pwd, Salt, Iter, Len, Block, Acc) ->
        U1 = hmac_md5(Pwd, <<Salt/binary, Block:32/unsigned-big-integer>>),
        Ux = pbkdf2_iterate(Pwd, Iter - 1, U1, U1),
        pbkdf2_blocks(Pwd, Salt, Iter, Len, Block + 1, <<Acc/binary, Ux/binary>>).
    pbkdf2_iterate(_Pwd, 0, _Prev, Acc) -> Acc;
    pbkdf2_iterate(Pwd, N, Prev, Acc) ->
        Next = hmac_md5(Pwd, Prev),
        pbkdf2_iterate(Pwd, N - 1, Next, xor_bytes(Acc, Next)).
    hmac_md5(Key0, Data) ->
        BlockSize = 64,
        Key = if byte_size(Key0) > BlockSize -> erlang:md5(Key0); true -> Key0 end,
        PadLen = BlockSize - byte_size(Key),
        K = <<Key/binary, 0:(PadLen * 8)>>,
        IPad = xor_bytes(K, binary:copy(<<16#36>>, BlockSize)),
        OPad = xor_bytes(K, binary:copy(<<16#5C>>, BlockSize)),
        erlang:md5(<<OPad/binary, (erlang:md5(<<IPad/binary, Data/binary>>))/binary>>).
    %% Byte-wise XOR — recursive zip, not cartesian product.
    xor_bytes(A, B) -> xor_bytes(A, B, []).
    xor_bytes(<<X, Ra/binary>>, <<Y, Rb/binary>>, Acc) ->
        xor_bytes(Ra, Rb, [X bxor Y | Acc]);
    xor_bytes(<<>>, <<>>, Acc) ->
        list_to_binary(lists:reverse(Acc)).
    ERLEOF
    erlc -o "$BEAMS_DIR" "$CRYPTO_TMP/crypto.erl"
    cat > "$BEAMS_DIR/crypto.app" << 'APPEOF'
    {application,crypto,[{modules,[crypto]},{applications,[kernel,stdlib]},{description,"Crypto shim for iOS (HTTP-only; no OpenSSL)"},{registered,[]},{vsn,"5.6"},{mod,{crypto,[]}}]}.
    APPEOF
    rm -rf "$CRYPTO_TMP"

    echo "=== Copying ssl from host OTP (pure Erlang — BEAM is platform-neutral) ==="
    # thousand_island lists :ssl as a required OTP application.
    # ssl is implemented entirely in Erlang (no NIFs), so the host macOS .beam
    # files run identically on the iOS simulator.
    # For HTTP-only Phoenix at loopback, ssl starts but no TLS sockets are opened.
    HOST_SSL_DIR=$(ls -d ~/.local/share/mise/installs/erlang/*/lib/ssl-* 2>/dev/null | sort -V | tail -1)
    if [ -n "$HOST_SSL_DIR" ]; then
        cp "$HOST_SSL_DIR/ebin/"*.beam "$BEAMS_DIR/"
        cp "$HOST_SSL_DIR/ebin/ssl.app" "$BEAMS_DIR/"
        echo "* ssl copied from $HOST_SSL_DIR"
    else
        echo "WARNING: ssl not found in host OTP — thousand_island may fail to start"
    fi

    # ── Sync OTP runtime to /tmp/otp-ios-sim ─────────────────────────────────────
    echo "=== Syncing OTP runtime to /tmp/otp-ios-sim ==="
    mkdir -p "/tmp/otp-ios-sim"
    rsync -a --delete "$OTP_ROOT/" "/tmp/otp-ios-sim/"

    echo "=== Copying Mob logos ==="
    cp "$MOB_DIR/assets/logo/logo_dark.png"  "/tmp/otp-ios-sim/mob_logo_dark.png"
    cp "$MOB_DIR/assets/logo/logo_light.png" "/tmp/otp-ios-sim/mob_logo_light.png"

    echo "=== Building and copying Phoenix static assets ==="
    # Build JS/CSS with esbuild + tailwind, then place them under
    # BEAMS_DIR/priv/static so Plug.Static can serve them.
    # code:lib_dir(:#{app_name}) resolves to BEAMS_DIR (the flat ebin directory),
    # so priv/static must live there. Without this, the LiveView JS never loads
    # and phx-click events cannot reach the server.
    mix assets.build
    mkdir -p "$BEAMS_DIR/priv/static"
    cp -r priv/static/. "$BEAMS_DIR/priv/static/"
    rsync -a "$BEAMS_DIR/priv/" "/tmp/otp-ios-sim/#{app_name}/priv/"

    echo "=== Spot-check ==="
    ls "$BEAMS_DIR/Elixir.#{module_name}.MobApp.beam"
    ls "$BEAMS_DIR/Elixir.#{module_name}.MobScreen.beam"

    # ── Compile C/ObjC/Swift ──────────────────────────────────────────────────────
    echo "=== Compiling native sources ==="
    BUILD_DIR=$(mktemp -d)
    SWIFT_BRIDGING="$MOB_DIR/ios/MobDemo-Bridging-Header.h"

    $CC -fobjc-arc -fmodules $IFLAGS \\
        -c "$MOB_DIR/ios/MobNode.m" -o "$BUILD_DIR/MobNode.o"

    xcrun -sdk iphonesimulator swiftc \\
        -target arm64-apple-ios16.0-simulator \\
        -module-name #{display_name} \\
        -emit-objc-header -emit-objc-header-path "$BUILD_DIR/MobApp-Swift.h" \\
        -import-objc-header "$SWIFT_BRIDGING" \\
        -I "$MOB_DIR/ios" \\
        -parse-as-library \\
        -wmo \\
        "$MOB_DIR/ios/MobViewModel.swift" \\
        "$MOB_DIR/ios/MobRootView.swift" \\
        -c -o "$BUILD_DIR/swift_mob.o"

    $CC -fobjc-arc -fmodules $IFLAGS \\
        -I "$BUILD_DIR" \\
        -DSTATIC_ERLANG_NIF \\
        -c "$MOB_DIR/ios/mob_nif.m"   -o "$BUILD_DIR/mob_nif.o"

    $CC -fobjc-arc -fmodules $IFLAGS \\
        -c "$MOB_DIR/ios/mob_beam.m"  -o "$BUILD_DIR/mob_beam.o"

    $CC $IFLAGS \\
        -c "$MOB_DIR/ios/driver_tab_ios.c" -o "$BUILD_DIR/driver_tab_ios.o"

    $CC -fobjc-arc -fmodules $IFLAGS \\
        -I "$BUILD_DIR" \\
        -c ios/AppDelegate.m  -o "$BUILD_DIR/AppDelegate.o"

    $CC -fobjc-arc -fmodules $IFLAGS \\
        -c ios/beam_main.m    -o "$BUILD_DIR/beam_main.o"

    # ── Link ───────────────────────────────────────────────────────────────────────
    echo "=== Linking #{display_name} binary ==="
    xcrun -sdk iphonesimulator swiftc \\
        -target arm64-apple-ios16.0-simulator \\
        "$BUILD_DIR/driver_tab_ios.o" \\
        "$BUILD_DIR/MobNode.o" \\
        "$BUILD_DIR/swift_mob.o" \\
        "$BUILD_DIR/mob_nif.o" \\
        "$BUILD_DIR/mob_beam.o" \\
        "$BUILD_DIR/AppDelegate.o" \\
        "$BUILD_DIR/beam_main.o" \\
        $LIBS \\
        -lz -lc++ -lpthread \\
        -Xlinker -framework -Xlinker UIKit \\
        -Xlinker -framework -Xlinker Foundation \\
        -Xlinker -framework -Xlinker CoreGraphics \\
        -Xlinker -framework -Xlinker QuartzCore \\
        -Xlinker -framework -Xlinker SwiftUI \\
        -o "$BUILD_DIR/#{display_name}"

    # ── Bundle + install ───────────────────────────────────────────────────────────
    echo "=== Building .app bundle ==="
    APP="$BUILD_DIR/#{display_name}.app"
    rm -rf "$APP"
    mkdir -p "$APP"
    cp "$BUILD_DIR/#{display_name}" "$APP/"
    cp ios/Info.plist "$APP/"
    if [ -d "ios/Assets.xcassets/AppIcon.appiconset" ]; then
        ACTOOL_PLIST=$(mktemp /tmp/actool_XXXXXX.plist)
        xcrun actool ios/Assets.xcassets \\
            --compile "$APP" \\
            --platform iphonesimulator \\
            --minimum-deployment-target 16.0 \\
            --app-icon AppIcon \\
            --output-partial-info-plist "$ACTOOL_PLIST" \\
            2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Merge $ACTOOL_PLIST" "$APP/Info.plist" 2>/dev/null || true
        rm -f "$ACTOOL_PLIST"
    fi

    echo "=== Installing on simulator $SIM_ID ==="
    xcrun simctl install "$SIM_ID" "$APP"

    echo "=== Installing complete ==="
    """
  end

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
        patched = Regex.replace(~r/\)\s*$/, line, ", {hooks: {MobHook}})", global: false)
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

      Regex.match?(~r/hooks:\s*\{/, content) ->
        # hooks key already exists — prepend MobHook to it
        Regex.replace(~r/(hooks:\s*\{)/, content, "\\1MobHook, ", global: false)

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
