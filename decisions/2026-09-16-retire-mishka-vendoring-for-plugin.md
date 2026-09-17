# Retire Mishka vendoring; depend on the `:mob_mishka` plugin

- Date: 2026-09-16
- Status: accepted
- Issue: MOB-252 (part of MOB-246 extraction epic)
- Supersedes:
  [`2026-09-11-default-app-vendors-mishka-showcase.md`](2026-09-11-default-app-vendors-mishka-showcase.md)
  — the vendoring decision recorded there is unwound here.

## Context

The 2026-09-11 decision picked vendoring because it was the only shape
that worked at the time: `mishka_chelekom` didn't ship its
`priv/mob` templates to Hex, and there was no other path to get the
composites into a generated app. That decision listed three costs:

- Regenerating an app pulls a fresh snapshot; user edits to a
  composite diverge from upstream forever.
- A bespoke `mix mob_new.sync_mishka` couples the mob_new archive
  release cadence to Mishka's source.
- The generated `config :mob, :extra_tags` block is fenced +
  regenerated, so any local edit is lost on the next sync.

The MOB-246 extraction epic makes vendoring optional. `:mob_mishka` is
a Hex plugin (private during the extraction spike). MOB-247 in mob
teaches `Mob.Sigil` to read plugin manifests at compile time, so the
`~MOB` sigil recognises the composite tags without an `extra_tags`
config edit. MOB-251 in mob_mishka adds `mix mob_mishka.gen <name>`
which ejects a specific composite into the user's `lib/` for editing;
a boot-time `override_namespace` config makes the ejected copy win.

Together those unblock replacing vendoring with a normal dep + an
opt-in eject flow.

## Decision

The generated app's `mix.exs` declares `{:mob_mishka, "~> 0.0"}`. The
plugin ships the composites; nothing under
`priv/templates/mob.new/lib/app_name/components/mishka_*.ex.eex`
exists any more. `showcase.ex.eex`, `showcase/**` and
`theme_bar.ex.eex` stay — they are app-owned presentation logic that
consumes the plugin's composites via `<Mishka…>` tags. Their aliases
were rewritten from `<%= module_name %>.Components.Mishka*` to
`MobMishka.Components.Mishka*` so an unedited app reaches the plugin.

The bespoke `mix mob_new.sync_mishka` and `priv/mishka_sync.txt` are
deleted. Nothing left to sync.

The template's generated `config/config.exs` keeps a fenced
`config :mob, :extra_tags` block for now as a compatibility bridge:
older mob releases (before MOB-247 lands) can't read the plugin's
manifest, so the sigil would warn on `<MishkaTabs>` etc. Once the
generated `{:mob, ...}` floor is bumped past MOB-247's release, the
block comes off. The migration ticket (MOB-253) tracks that.

The `local: true` codepath in `MobNew.ProjectGenerator` grew a
`resolve_mob_mishka_dep_local/0` helper: `MOB_MISHKA_DIR` env var,
then `./mob_mishka`, then `../mob_mishka` — falls back to
`{:mob_mishka, "~> 0.0"}` when none exist. This lets integration
tests that run generated projects use a local mob_mishka checkout
while the plugin isn't on Hex yet.

## Consequences

- `mix mob.new foo` produces an app with ~75 fewer files than before.
- Regenerating never re-clobbers a user-edited composite (there are
  none to edit; if they want to, they `mix mob_mishka.gen`).
- mob_new releases decouple from mishka_chelekom releases. Upgrading
  the Mishka composites is `mix deps.update mob_mishka` for users.
- The scaffolded Mob.ScreenCase integration test (tagged
  `:integration`, excluded by default) can only pass once the mob
  version the generated app pins ships MOB-247. Until then it warns
  as expected under `--warnings-as-errors`; MOB-253 removes the
  `extra_tags` bridge and the test starts working end-to-end.
- Once `mob_mishka` publishes to Hex, drop the local-path fallback in
  `resolve_mob_mishka_dep_local/0` and simplify to
  `{:mob_mishka, "~> 0.X"}`.
