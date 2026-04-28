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
mix mob.install    # first-run setup: download OTP runtime, generate icons, write mob.exs
```

### Options

| Option | Description |
|--------|-------------|
| `--ios` | Generate iOS boilerplate only (skip `android/`) |
| `--android` | Generate Android boilerplate only (skip `ios/`) |
| `--liveview` | Wrap a Phoenix LiveView app in a Mob WebView (combines with `--ios` / `--android`) |
| `--no-install` | Skip `mix deps.get` after generation |
| `--dest DIR` | Create the project in DIR (default: current directory) |
| `--local` | Use `path:` deps pointing to local mob/mob_dev repos — see below |
| `--no-ios` | Alias for `--android` (skip iOS boilerplate) |
| `--no-android` | Alias for `--ios` (skip Android boilerplate) |

`mix mob.install`, `mix mob.deploy`, and `mix mob.doctor` detect the project's
platform set from on-disk layout, so a single-platform project skips the
absent platform's setup automatically (no Android OTP download, no iOS
toolchain check, etc.).

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

It also pre-fills `mob.exs` with your actual local paths so `mix mob.install`
skips the path configuration prompts and proceeds straight to OTP download and
icon generation.

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
