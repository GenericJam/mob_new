# mob_new

Project generator for the [Mob](https://hexdocs.pm/mob) mobile framework. Installs a global `mix mob.new` command.

[![Hex.pm](https://img.shields.io/hexpm/v/mob_new.svg)](https://hex.pm/packages/mob_new)

## Installation

`mob_new` is a Mix archive — install it globally, not as a project dependency:

```bash
mix archive.install hex mob_new
```

## Usage

```bash
mix mob.new my_app
cd my_app
mix mob.install    # first-run setup: local paths, download OTP runtime
```

The generated project ships the Mob logo as its launcher icon (Android
`res/mipmap-*/ic_launcher.png`, iOS `ios/Assets.xcassets/AppIcon.appiconset`),
so the first native build needs no extra step. To replace it, add
`{:image, "~> 0.54"}` to your deps and run `mix mob.icon --source my_logo.png`
(add `--adaptive` for an Android adaptive icon).

`mob.exs` is project configuration — activated plugins, plugin trust, styles —
and is meant to be committed. A clone without it activates no plugins, so the
native build leaves their NIFs out. Machine-specific overrides go in
`mob.local.exs`, which the generated `.gitignore` excludes and `mob.exs`
imports when present.

### Options

| Option | Description |
|--------|-------------|
| `--ios` | Generate iOS boilerplate only (skip `android/`) |
| `--android` | Generate Android boilerplate only (skip `ios/`) |
| `--liveview` | Wrap a Phoenix LiveView app in a Mob WebView (combines with `--ios` / `--android`) |
| `--no-install` | Skip `mix deps.get` after generation |
| `--deliver` | Wire the app for [mob_deliver](https://github.com/GenericJam/mob_deliver) (signed OTA + just-in-time screens) — see below. Native only; rejected with `--liveview` |
| `--dest DIR` | Create the project in DIR (default: current directory) |
| `--local` | Use `path:` deps pointing to local mob/mob_dev repos — see below |
| `--no-ios` | Alias for `--android` (skip iOS boilerplate) |
| `--no-android` | Alias for `--ios` (skip Android boilerplate) |

`mix mob.install`, `mix mob.deploy`, and `mix mob.doctor` detect the project's
platform set from on-disk layout, so a single-platform project skips the
absent platform's setup automatically (no Android OTP download, no iOS
toolchain check, etc.).

### Signed OTA and just-in-time screens (`--deliver`)

`mix mob.new my_app --deliver` adds `:mob_deliver` (and, dev-only,
`:mob_deliver_server` for its publish task), activates the plugin in
`mob.exs`, and boots through `MobDeliver.root_screen/1`. It also generates:

- `mob_deliver_signing.key`: a fresh Ed25519 publish key (mode 0600,
  gitignored; keep it as a CI secret). Its public half is in
  `config/config.exs` as `:trusted_publish_key`, next to `app`, `channel`,
  `store_url`, and the `endpoint` you point at your server. The update gate
  reads the app's version from the binary (`Mob.Device.app_version/0`).
- `mobile/my_app/welcome_screen.ex`: an example **expansion screen**, opened
  from the home screen. `mobile/` is not in `elixirc_paths`, so it is never
  compiled into the app binary. The installed app fetches each screen the
  first time it is opened. Screens in `lib/my_app/` ship in the binary as usual.

Publish, then serve the output directory with `MobDeliverServer.Plug`
(`storage: {MobDeliverServer.Storage.FS, root: "mob_deliver_publish"}`):

```bash
mix mob_deliver.publish --app com.example.my_app \
  --key-file mob_deliver_signing.key --out mob_deliver_publish
```

The output stays outside `priv/` on purpose: mob_dev copies `priv/` into the
native bundle.

### Local development mode (`--local`)

> **This flag is for Mob framework contributors and library authors testing
> unpublished changes. It is not intended for app developers — use the standard
> `mix mob.new my_app` instead.**

#### Installing the local mob_new archive

When working on mob_new itself, build and force-install the archive to pick up your changes:

```bash
cd ~/code/mob_new && mix archive.build && mix archive.install $(ls mob_new-*.ez | tail -1) --force
```

Verify it's active:

```bash
mix archive        # mob_new should appear with the updated version
mix mob.new --help
```

If you are working on Mob itself and want to test your changes end-to-end
before publishing to Hex, pass `--local` to generate a project that depends on
your local checkouts instead of the published packages:

```bash
mix mob.new my_app --local
```

This generates `mix.exs` with `path:` deps:

```elixir
{:mob,     path: "/path/to/mob"},
{:mob_dev, path: "/path/to/mob_dev", only: :dev, runtime: false}
```

It also writes your local `mob_dir` to `mob.local.exs` (gitignored) so
`mix mob.install` skips the path configuration prompts and proceeds straight to
OTP download.

**Path resolution** (in order):

1. `MOB_DIR` / `MOB_DEV_DIR` environment variables
2. `./mob` / `./mob_dev` in the current directory (e.g. running from `~/code`)
3. `../mob` / `../mob_dev` relative to the current directory

```bash
# If mob and mob_dev live alongside each other in ~/code:
cd ~/code
mix mob.new my_app --local   # auto-detects ~/code/mob and ~/code/mob_dev

# Or set explicitly from anywhere:
MOB_DIR=~/code/mob MOB_DEV_DIR=~/code/mob_dev mix mob.new my_app --local
```

## What gets generated

```
my_app/
├── mix.exs
├── lib/
│   └── my_app/
│       ├── app.ex           # Mob.App entry point
│       └── home_screen.ex   # starter screen
├── android/
│   ├── build.gradle
│   └── app/
│       └── src/main/
│           ├── AndroidManifest.xml
│           └── java/com/mob/my_app/MainActivity.java
└── ios/
    ├── beam_main.m
    └── Info.plist
```

## Next steps after generation

First deploy (builds the native app and installs it):

```bash
mix mob.deploy --native
```

Day-to-day (hot-pushes changed BEAMs, no native rebuild):

```bash
mix mob.deploy        # push + restart
mix mob.watch         # auto-push on file save
mix mob.connect       # open IEx connected to the running device node
```

## Documentation

Full guide at [hexdocs.pm/mob](https://hexdocs.pm/mob), including [Getting Started](https://hexdocs.pm/mob/getting_started.html), screen lifecycle, components, navigation, and live debugging.

## Development

Clone, then run once:

```bash
mix setup
```

That fetches deps and activates the repo's git hooks (`.githooks/pre-push`):
`mix format --check`, `mix credo --strict` (incl. ExSlop), and `mix compile --warnings-as-errors` run on every push, plus the full test
suite when `mix.exs` changes — the same gate CI enforces before publishing.
