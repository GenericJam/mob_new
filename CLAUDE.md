# mob_new — Agent Instructions

**Read [`AGENTS.md`](AGENTS.md) first**, then [`~/code/mob/AGENTS.md`](../mob/AGENTS.md)
for the system view. They cover the three-repo topology, generator
gotchas (LV blocklist, eager template defaults, App ID name validation),
and cross-cutting pre-empt-failure rules. This file goes deeper on
archive-build mechanics.

> **Keep AGENTS.md up to date** when you change template structure, add
> to the LV blocklist, or hit a generator gotcha. Same commit, not a
> follow-up.

For the in-flight build-system refactor (Mix → Igniter → Zig build),
see [`~/code/mob/build_system_migration.md`](../mob/build_system_migration.md) —
multi-month sequenced plan; phase ownership lives there. mob_new owns the
heaviest absolute change (build templates + LV patcher).

## Worktrees

**Default assumption: work happens in a git worktree.** The user runs
multiple agents in parallel; each task in its own worktree prevents conflicts
between agents and keeps `master` clean while work is in flight.

If you're assigned a task and worktree usage **isn't mentioned**, ask:

> "Should I use a worktree for this?"

The user will answer:

- **yes** — long task, or other agents may be working in parallel; create a
  worktree (use `EnterWorktree` or spawn the work via Agent with
  `isolation: "worktree"`)
- **no** — quick change with no parallel agent work; work in-place on the
  current branch

If the user explicitly says "use worktrees" up front, do so without asking.
If the task is trivially small (single-file doc edit, one-line config change)
and clearly won't conflict with anything, working in-place is acceptable —
but if in doubt, ask.

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

## Tests cover the generator too, not just runtime code

`mob_new` is mostly a code generator + a Mix archive — so the
"non-runtime" half is most of what's here. Same testing discipline
as the other repos: **every CLI command and every generator helper
gets coverage.**

- `mix mob.new` argument parsing, flag handling, `--help` output.
- Template-rendering helpers (`MobNew.ProjectGenerator.*`):
  test against tmpdir fixtures + verify rendered output where
  feasible (the existing `--only lint` ktlint run is the
  template-as-output check).
- Path resolution / `--local` override semantics — the recent
  `local_mob_new_priv/1` got 5 tests precisely because it
  affects which templates every generated project sees, and a
  bug there silently re-introduces issues we already fixed
  upstream.
- AST patchers (`MobNew.LiveViewPatcher`): test the
  before-and-after shapes, including idempotency under repeat
  application.

**Goal: find bugs in CI before users hit them.** Every "regenerate
test_migration → hit the same warning we already fixed" cycle this
session was the templates lagging master because some lookup
wasn't pinned by a test. Treat that as a bug-class-to-eliminate,
not a one-off.

When you change a template, run `mix test --only lint` (the
generate-then-ktlint check) AND add a focused assertion on the
specific behavior you changed if it isn't already covered.

## Pre-commit checklist

Before committing changes, run **all** in this order:

```bash
mix test            # full suite must pass (call out any pre-existing flake explicitly)
mix format          # apply Elixir formatting
mix credo --strict  # **whole tree, not just changed files** — includes ExSlop (catches AI-generated patterns: blanket rescue, narrator docs, etc). Pre-existing issues are tracked separately, but new ones (including in tests) must be fixed
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

## Connecting an IEx session to a running mob app (Mac → device BEAM)

Drive any running mob app from a Mac-side IEx via Erlang
distribution. Beats `adb shell input tap` for anything
state-related — you get full RPC into the device BEAM.

### The happy path (single device)

```bash
cd /path/to/your_mob_app

mix mob.connect            # starts IEx connected to all devices
# or
mix mob.connect --no-iex   # sets up tunnels, prints node names, exits
```

Then from any other IEx (or one-shot script) on the Mac:

```bash
elixir --name probe@127.0.0.1 --cookie mob_secret -e '
node = :"your_app_android_<suffix>@127.0.0.1"
Node.connect(node)
:rpc.call(node, YourApp.Module, :function, [args])
'
```

The cookie defaults to `:mob_secret` (set by `Mob.Dist.ensure_started`
in your app's `on_start/0`). `--name` (long names) is required when
the device node uses a numeric host like `@10.0.0.120`.

### Multi-Android limitation (mob_dev current behaviour)

`mob_dev` derives the Android dist node name from the device's IP,
which is identical (`10.0.2.x`) for every emulator. Two emulators
both try to register `your_app_android_emulator36x5x10x0` in EPMD
and the second fails with `eaddrinuse`. Symptom in
`mix mob.connect` output:

```
sdk_gphone64_arm64: timed out waiting for your_app_android_emulator36x5x10x0@127.0.0.1
```

Workarounds:
1. Only have one emulator running.
2. Pick the emulator you care about and verify the other side via
   `adb logcat`.

### Fixing adb-forward port mismatch

`mob_dev` assigns dist ports by index (`9100` for the first device,
`9101` for the second, …) but EPMD broadcasts the *device-side*
port (always `9100`). When EPMD says "node X is at port 9100",
your IEx connects to `localhost:9100` — which may be an `adb
forward` to a different device, or to nothing. Symptom:

```elixir
Node.connect(:"your_app_android_<suffix>@127.0.0.1")
#=> false
```

Repoint `localhost:9100` at the device whose BEAM you want:

```bash
adb forward --list                           # see what's there
adb -s <serial> forward tcp:9100 tcp:9100    # 9100 host → 9100 device
```

For physical-device-on-Wi-Fi targets (iPhone, real Android), the
node name uses the device IP directly (`@10.0.0.120`) and dist
goes through real network — no adb-forward dance required.

### Inspecting state that contains opaque resources

Several mob/Pigeon operations return values containing opaque NIF
resources (e.g. `Pythonx.Object`, ETS table refs). These cannot
cross Erlang distribution: `:rpc.call/4` will fail with `:badrpc`
on the way back. Pattern: do the resource-touching work *on the
device side* and return primitives (strings, maps, ints).

Example — bad (returns `Pythonx.Object`, dies on dist boundary):

```elixir
:rpc.call(node, Pythonx, :eval, [src, %{}])  # returns {Pythonx.Object, _}; cannot serialize
```

Good — wrap in a helper module compiled into the app:

```elixir
defmodule YourApp.IexHelpers do
  def python_state do
    {obj, _} = Pythonx.eval("...", %{})
    Jason.decode!(Pythonx.decode(obj))   # plain map; safe to ship
  end
end
```

Then `:rpc.call(node, YourApp.IexHelpers, :python_state, [])` works.
Pigeon has `Pigeon.IexHelpers` exactly for this purpose — copy
that pattern when adding device-side debugging surfaces.

### What to reach for first

Write small named functions in `<your_app>.IexHelpers`, push with
`mix mob.deploy`, call by RPC. That keeps the Mac-side script
minimal and debuggable, and the helpers double as documentation
of the operations you actually need.
