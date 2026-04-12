# mob_new — Agent Instructions

`mob_new` is a Mix archive — a self-contained `.ez` file that installs a global
Mix task (`mix mob.new`). It is **not** a regular dependency; it ships as a
`mix archive.install` package.

## Building and installing the archive locally

```bash
cd ~/code/mob_new
mix archive.build          # produces mob_new-<version>.ez in the current dir
mix archive.install mob_new-0.1.1.ez --force   # installs it globally
```

After installing, `mix mob.new` is available in any directory.

To verify the install:
```bash
mix archive                # lists installed archives — mob_new should appear
mix mob.new --help
```

To uninstall:
```bash
mix archive.uninstall mob_new
```

## Testing the full generator flow

```bash
mix mob.new /tmp/my_test_app
cd /tmp/my_test_app
mix mob.install
```

## Publishing to Hex

```bash
mix hex.publish archive    # publishes the .ez archive (not a library package)
```

## Key files

- `lib/mix/tasks/mob.new.ex` — `mix mob.new APP_NAME` task
- `lib/mob_new/project_generator.ex` — EEx template rendering
- `priv/templates/mob.new/` — project template files
- `mix.exs` — version lives here; bump before publishing

## Running tests

```bash
mix test
```
