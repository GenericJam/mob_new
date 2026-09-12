# AGENTS.md — mob_new

You're in **mob_new**, the project generator. Read
[`~/code/mob/AGENTS.md`](../mob/AGENTS.md) first for the system view, the
three-repo topology, the cross-cutting pre-empt-failure rules, and the
**"Don't write this slop"** list (AI-generated patterns to avoid at write
time, not after credo flags them). The notes below are mob_new-specific.

## What this repo is

A Mix archive (`mix archive.install hex mob_new`) that installs a global
`mix mob.new` task. Generates either:

- **Native Mob projects** — `mix mob.new my_app` — Elixir-driven SwiftUI/Compose UI.
- **LiveView wrappers** — `mix mob.new my_app --liveview` — Phoenix LiveView running
  on-device, served to a WKWebView/WebView.

Templates live at `priv/templates/mob.new/`, rendered with EEx by
`MobNew.ProjectGenerator`. The LiveView path additionally runs `mix phx.new`
as a subprocess and patches the result via `MobNew.LiveViewPatcher`.

## Building and installing locally

```bash
cd ~/code/mob_new
mix archive.build                          # produces mob_new-<version>.ez
mix archive.install mob_new-0.1.27.ez --force
mix archive                                # verify install
```

To publish a new version: bump `version:` in `mix.exs`, then
`mix hex.publish archive`.

## Verification fidelity ladder

The output of this repo is somebody's first five minutes with Mob, and it is a
generator: the code here can be perfect while the thing it emits does not build.
Run every applicable lower rung, plus the highest rung the change actually
reaches, and say which rung you stopped at.

1. **Static.** `mix format --check-formatted`, `mix credo --strict` (ex_slop
   included), `mix compile --warnings-as-errors`.
2. **Host unit.** `mix test`. Proves the generator's logic. Proves nothing about
   the project it writes.
3. **A generated project, generated.** `mix test --include integration` runs
   real `mix phx.new` subprocesses into tmp dirs. Slower, and the only rung that
   reads the actual output. Run it before publishing.
4. **The generated project builds native and boots.** Generate, then
   `mix mob.deploy --native` to a simulator or emulator and confirm the app
   reaches its first screen. Templates compile as text at every rung above this
   one; this is the first that compiles them as code.
5. **The generated project on a physical device, release variant.** Debug
   defaults hide release packaging bugs. `useLegacyPackaging true` exists in
   `build.gradle.eex` because AGP leaves native libs packed in a release App
   Bundle while the BEAM needs them on the filesystem — debug defaulted to
   `true`, which masked it until a Play install crashed on launch.
6. **From the installed archive, built from the packed Hex package.** The
   generator ships as a Mix archive, and archive-reachable code must carry its
   compile-time resources inside the Hex package. Testing from the repo checkout
   proves nothing about that path: build the archive, install it, and generate
   from the installed copy. Watch for a stale global archive shadowing the repo
   task.

Every rung above exists because something got through the one below it.

Two rules that outrank the list:

- **Never substitute a lower rung because a higher one is slow, broken, or
  inconvenient.** Fix the harness, open an issue, or state plainly that the rung
  was unavailable and why. An unavailable rung is a fine answer. A silently
  skipped one is not.
- **Verify effects, not exit codes.** An exit code proves the generator ran. It
  does not prove the project it wrote will build for anyone else.

## Things that bite specifically in mob_new

- **The LV path skips Phoenix-owned files.** When generating a LiveView
  project, the native template's `mix.exs`, `config/`, `lib/<app>/`, etc.
  must NOT clobber what `mix phx.new` produced. The blocklist is in
  `liveview_phoenix_owned?/3` (public for testing). If you add a new path
  to the native template and don't update the blocklist, LV projects ship
  with a broken (overwritten) Phoenix config.

- **LiveView generation preserves existing dotfiles.** It adds Mob's
  `.tool-versions` only when `mix phx.new` did not create one; never route the
  LiveView path through the native `write_dotfiles/2` overwrite behavior.

- **Archive compile-time resources must ship in the Hex package.** The exact
  Zig pin lives in `priv/zig-version`, not the repository-root `.tool-versions`:
  Hex includes `priv/`, but omits root dotfiles. Keep the two pins in lockstep;
  the packed-artifact regression builds and installs from unpacked Hex source.

- **Template defaults eagerly evaluate.** `System.get_env("ROOTDIR", Path.expand("~/..."))`
  inside a template raises on Android (no `HOME`). The fix used `case` /
  `||` for laziness — see `home_screen.ex.eex` `rootdir/0` helper. Don't
  reintroduce eager defaults in templates.

- **Bundle ID / app name affect Apple App ID validation.** Apple rejects
  auto-generated App ID display names that exceed ~30 chars or contain
  characters their validator dislikes (underscores have been flagged).
  Long snake_case app names (`another_political_name_app`) hit this.
  `mob.provision` now rewrites the error to a hint, but the generator
  itself doesn't enforce length — that's a deliberate trade-off so users
  can still pick descriptive names; we surface the issue at provision time.

- **Port 4200 is hardcoded for LiveView projects.** All LV templates set
  the Phoenix endpoint to 127.0.0.1:4200. Two installed apps collide; only
  one runs at a time. Tracked in `mob/issues.md` #4 — fix involves
  hashing the bundle id.

- **`inject_deps/3` uses Sourceror AST, not regex (Phase 5 iter 1).**
  Patches to the user's mix.exs deps list go through
  `Sourceror.parse_string → Macro.prewalk → Sourceror.to_string`.
  Don't reach for a regex on `defp deps do\s*\[` — the AST walk is
  robust against Phoenix-version drift + formatter shape changes
  that bit the old regex twice. When extending: append to the list
  found by the `prewalk` clause matching `def(p) deps do [...]`.
  The shorthand `defp deps, do: [...]` form isn't matched yet —
  it's a separate AST shape and lands as a future iter when a real
  project hits it.

- **Sourceror is a runtime dep.** Added in Phase 5 iter 1. It's
  bundled into the .ez archive so `mix mob.new` users don't need
  to install it separately, but it does add ~1 MB to the archive
  size. If we add more AST tooling (Igniter, etc.) consider whether
  the archive bloat is worth it; Sourceror alone is the floor.

- **`apply_liveview_patches` is the orchestration spine.** New LV-specific
  generated files / config patches go through it. The order matters
  (Phoenix files generated by `phx.new`, then patches, then native
  boilerplate, then LV-specific configs). Document any reordering.

- **Native apps ship showcase plugins by default (0.4.2).** `mix.exs.eex`
  depends on `mob_camera` / `mob_location` / `mob_biometric` / `mob_themes`,
  and `mob.exs.eex` activates them (`config :mob, :plugins` / `:styles` /
  `:default_style`). The home screen does NOT hardcode their nav entries —
  it enumerates `Mob.Plugins.screens/0` and renders a button per
  manifest-declared demo screen, so adding/removing a plugin needs no home
  edit. These are native-only: the activation lives in `mob.exs.eex` (the LV
  path overwrites mob.exs via `LiveViewPatcher.mob_exs_content/2` and uses
  Phoenix's own mix.exs), so LiveView projects don't get them. The
  `--local` path dep is `override: true` so a local mob checkout satisfies the
  Hex plugins' `mob ~> 0.7` requirement.

- **Name consistency isn't ownership.** `MobNew.Templates.Lint.external_fun_jni_consistency/2`
  only checks that Kotlin's `external fun nativeFoo` and C's
  `Java_..._MobBridge_nativeFoo` agree on the NAME — it can't tell which
  Kotlin class/object actually encloses the declaration. `nativeFoo`
  declared on the wrong object (or nested inside a class within the right
  one) passes that check and throws `UnsatisfiedLinkError` on first call
  — see MOB-98. `native_funs_owned_by_mob_bridge/1` closes that gap
  (brace-depth aware, not just byte-position aware) and runs as part of
  `check_kotlin/1`'s aggregate.

- **Android sheet state needs node identity.** Keep `MobSheet` keyed by the
  sheet node's stable `id`, with the constant fallback for un-ID'd sheets.
  Otherwise different sheets in one Compose slot share dismissal state and a
  stale callback can hide the replacement. Canonicalize every JSON-serializable
  ID type; only a truly absent `id` uses the legacy constant-slot fallback.
  Native stale-event protection belongs to Mob's generation-tagged handles,
  not to generator-side root tracking.

- **Android list state must not use a full event handle as identity.** Native
  handles include a render generation and change on every render. Prefer the
  list node's canonical `id`; for an un-ID'd list with `on_end_reached`, retain
  only the low-byte slot. Using the full handle resets scroll and leaks one
  `LazyListState` per render.

- **Kotlin imports: no comments or blank lines inside the import block.**
  The ktlint test runs `--format` first and then checks; `import-ordering`
  refuses to autocorrect when the import list carries a comment, so the
  template fails lint for a line that looks harmless. Section banners go
  above the first import or below the last.

- **`WindowInsets` is two classes.** `MobBridge.kt.eex` imports
  `android.view.WindowInsets` for the decor-view inset reads; the Compose
  one (`WindowInsets.safeDrawing`, used by `MobAnchored`) comes in as
  `ComposeWindowInsets`. Importing both unaliased is an ambiguity error.

- **Every `setRootJson` bumps `RootState.epoch`.** Controlled widgets
  (`MobTextField`, `MobSlider`) resync on `LocalRenderEpoch`, not on
  `remember(node.props["value"])`: an equal value after a rejected keystroke
  never re-keys a `remember`. `navKey` stays the navigation-only signal
  (`LocalSlotEpoch`); do not fold the two together.

## The default app is the Mishka Chelekom showcase (vendored)

`priv/templates/mob.new/lib/app_name/{components,showcase,showcase.ex,theme_bar.ex}`
and `test/app_name/showcase_test.exs.eex` are **not hand-edited**. They are
copied from the `mishka_chelekom` monorepo's `development/mob` app (itself a
`mix mob.new` project) by

```bash
mix mob_new.sync_mishka ~/code/mishka_chelekom   # then regenerate + test a project
```

which rewrites `MishkaMob` → `<%= module_name %>` and `mishka_mob` →
`<%= app_name %>`, clears the target directories first, refills the fenced
`config :mob, :extra_tags` block in `config/config.exs.eex` from the catalog in
`showcase.ex`, and stamps the upstream commit into `priv/mishka_sync.txt`. Fix
a component upstream (Kevin's fork tracks it) and re-sync; a local edit to a
vendored template is lost on the next sync. `home_screen.ex.eex`, `app.ex.eex`
and `home_screen_test.exs.eex` are hand-maintained and carry the `--blank`
gating as two whole modules in one file rather than interleaved fragments;
`blank_excluded?/3` is what keeps the vendored tree out of a blank app.

Verifying a template change against a real project from a worktree needs three
env vars: `--local` resolves templates from `$HOME/code/mob_new` unless
`MOB_NEW_DIR` points at the worktree, and `MOB_DIR` / `MOB_DEV_DIR` must name
the local mob checkouts. The globally installed `mob_new` archive shadows the
repo task, so run with `MIX_ARCHIVES` set to a temp dir that contains only a
copy of the `hex-*` archive (an empty dir also hides Hex).

## Tests

```bash
mix test                        # unit tests (fast)
mix test --include integration  # also runs `mix phx.new` subprocesses (~minute)
```

The integration tests generate real LV projects in tmp dirs to verify the
end-to-end output. Worth running locally before publishing a new version.

From a git worktree (anything not sitting beside `../mob`), the two `--local`
tests need `MOB_DIR=~/code/mob MOB_DEV_DIR=~/code/mob_dev mix test`; the
generator resolves local deps relative to the project's parent otherwise.

To compile a generated Android app without touching an attached phone
(another session may own it), put a stub `adb` first on `PATH` that prints an
empty `devices` list; `mix mob.deploy --android --native` then builds the APK
and exits 0 with nothing to push to.

## Keep this file up to date

When you add a new template path, change the LV phx-owned blocklist, or
hit a new generator gotcha — update this file in the same commit.
