# mob_new — Agent Instructions

**Read [`AGENTS.md`](AGENTS.md) first**, then [`~/code/mob/AGENTS.md`](../mob/AGENTS.md)
for the system view. They cover the three-repo topology, generator
gotchas (LV blocklist, eager template defaults, App ID name validation),
and cross-cutting pre-empt-failure rules. This file goes deeper on
archive-build mechanics.

> **Keep AGENTS.md up to date** when you change template structure, add
> to the LV blocklist, or hit a generator gotcha. Same commit, not a
> follow-up.

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

## Pre-commit checklist

Before committing changes, run **all** in this order:

```bash
mix test            # full suite must pass (call out any pre-existing flake explicitly)
mix format          # apply Elixir formatting
mix credo --strict  # address new issues; pre-existing ones are tracked separately
mix test --only lint  # generate project + ktlint generated Kotlin (requires brew install ktlint)
```

## Template linting strategy

EEx templates (`priv/templates/**/*.kt.eex`, `*.m.eex`, etc.) cannot be
linted directly — the `<%= %>` syntax breaks all native language parsers.

**The solution:** generate a real project, lint the output.

```bash
mix test --only lint          # runs the generate-then-ktlint test in the suite
```

If ktlint reports a violation, the fix goes in the `.kt.eex` template, not
the generated file. The generated file is a canary; the template is the source.

This approach means every template change is validated against the real
Kotlin style guide automatically. Normalized generated code also makes
Claude-assisted work more reliable — consistent patterns are easier to
reason about and modify correctly.

When changing the EEx templates under `priv/templates/`, also generate a
fresh project and verify it compiles before committing:

```bash
mix mob.new /tmp/foo && cd /tmp/foo && mix mob.install
```
