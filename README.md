# mob_new

Project generator for the [Mob](https://hexdocs.pm/mob) mobile framework.

## Usage

Install the archive:

```bash
mix archive.install hex mob_new
```

Generate a new project:

```bash
mix mob.new my_app
cd my_app
mix mob.install
```

`mix mob.install` detects your local OTP and Elixir paths, writes `mob.exs`, and generates the app icon.

## Documentation

See [hexdocs.pm/mob](https://hexdocs.pm/mob) for the full guide — screens, state management, live debugging, and deploying to Android and iOS.
