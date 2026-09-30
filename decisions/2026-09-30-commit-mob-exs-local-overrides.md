# Commit mob.exs; machine-local overrides live in mob.local.exs
- Date: 2026-09-30
- Status: accepted

## Context
Generated projects gitignored `mob.exs` on the theory that it held only
machine paths (`mob_dir`, `elixir_lib`). It also holds project config:
`config :mob, :plugins` (activation), `:trusted_plugins`, `:styles`,
`:default_style`, `:acknowledge_unsafe_plugins`, `:static_nifs`. A clone got
no `mob.exs`, activated zero plugins, and the native build linked no plugin
NIFs — it succeeded, and plugin calls raised `:nif_not_loaded` at runtime
(MOB-286).

## Decision
`mob.exs` is committed. Its default values are portable
(`mob_dir: Path.join(File.cwd!(), "deps/mob")`, `elixir_lib` from
`MOB_ELIXIR_LIB` or the running Elixir). Machine-specific overrides go in
`mob.local.exs`, which the generated `.gitignore` excludes and `mob.exs`
imports as its last statement, only when the file exists:

    if File.exists?(Path.join(__DIR__, "mob.local.exs")), do: import_config("mob.local.exs")

Last, so local values win. Conditional, so a clone without the file reads
cleanly. `import_config` works because every mob_dev reader uses
`Config.Reader.read!/1` with imports enabled (the default).

`--local` writes its checkout `mob_dir` into `mob.local.exs`; it no longer
pins `elixir_lib`, since the portable default already resolves the running
Elixir at read time.

## Consequences
- mob_dev tasks that write machine paths into `mob.exs` (`mix mob.install`'s
  path prompt, `mix mob.adopt.mob_exs --local`) and that gitignore `mob.exs`
  (`mix mob.adopt.mob_exs`) must follow the same split; that change lives in
  mob_dev.
- The import must stay the last statement for local values to win. mob_dev
  tasks that write into `mob.exs` (plugin trust, `mix mob.deploy
  --beam-flags`, `mix mob.enable` liveview_port) insert above the import for
  that reason — see mob_dev's
  `decisions/2026-09-30-mob-local-exs-overrides.md`. mob_dev versions from
  before that change append after the import, so their value overrides
  `mob.local.exs`.
