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
| `--no-install` | Skip `mix deps.get` after generation |
| `--dest DIR` | Create the project in DIR (default: current directory) |

## What gets generated

```
my_app/
├── mix.exs
├── lib/
│   └── my_app/
│       ├── app.ex           # Mob.App entry point
│       └── hello_screen.ex  # starter screen
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
