# mob_new — Agent Instructions

You're in **mob_new**, the project generator. Read
[`~/code/mob/AGENTS.md`](../mob/AGENTS.md) first for the system view, the
three-repo topology, the cross-cutting pre-empt-failure rules, and the
**"Don't write this slop"** list (AI-generated patterns to avoid at write
time, not after credo flags them). The notes below are mob_new-specific.

For the in-flight build-system refactor (Mix → Igniter → Zig build),
see [`~/code/mob/build_system_migration.md`](../mob/build_system_migration.md) —
multi-month sequenced plan; phase ownership lives there. mob_new owns the
heaviest absolute change (build templates + LV patcher).

## What this repo is

A Mix archive — a self-contained `.ez` file, **not** a regular dependency —
installed with `mix archive.install hex mob_new`, that installs a global
`mix mob.new` task. Generates either:

- **Native Mob projects** — `mix mob.new my_app` — Elixir-driven SwiftUI/Compose UI.
- **LiveView wrappers** — `mix mob.new my_app --liveview` — Phoenix LiveView running
  on-device, served to a WKWebView/WebView.

Templates live at `priv/templates/mob.new/`, rendered with EEx by
`MobNew.ProjectGenerator`. The LiveView path additionally runs `mix phx.new`
as a subprocess and patches the result via `MobNew.LiveViewPatcher`.

## Key files

- `lib/mix/tasks/mob.new.ex` — `mix mob.new APP_NAME` task
- `lib/mob_new/project_generator.ex` — EEx template rendering
- `priv/templates/mob.new/` — project template files
- `mix.exs` — version lives here; bump before publishing

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

## Building and installing the archive locally

```bash
cd ~/code/mob_new
mix archive.build                          # produces mob_new-<version>.ez in the current dir
mix archive.install mob_new-0.1.27.ez --force   # installs it globally
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

Bump `version:` in `mix.exs`, then:

```bash
mix hex.publish archive    # publishes the .ez archive (not a library package)
```

See also "Release flow" below.

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

## Tests

```bash
mix test                        # unit tests (fast)
mix test --include integration  # also runs `mix phx.new` subprocesses (~minute)
```

The integration tests generate real LV projects in tmp dirs to verify the
end-to-end output. Worth running locally before publishing a new version.

From a git worktree (anything not sitting beside `../mob`), the two `--local`
tests need `MOB_DIR=~/code/mob MOB_DEV_DIR=~/code/mob_dev mix test`; the
generator resolves local deps relative to the project's parent otherwise, and
the worktree path breaks that assumption. The tests "--local writes the mob
checkout path to mob.local.exs, not mob.exs" and "--local resolves both deps
from MOB_DELIVER_DIR / MOB_DELIVER_SERVER_DIR" in
`test/mob_new/project_generator_test.exs` demonstrate this pattern.

To compile a generated Android app without touching an attached phone
(another session may own it), put a stub `adb` first on `PATH` that prints an
empty `devices` list; `mix mob.deploy --android --native` then builds the APK
and exits 0 with nothing to push to.

### Tests cover the generator too, not just runtime code

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

## Pre-commit checklist

Before committing changes, run **all** in this order:

```bash
mix test            # full suite must pass (call out any pre-existing flake explicitly)
mix format          # apply Elixir formatting
mix credo --strict  # **whole tree, not just changed files** — includes ExSlop (catches AI-generated patterns: blanket rescue, narrator docs, etc). Pre-existing issues are tracked separately, but new ones (including in tests) must be fixed
mix test --only lint  # generate project + ktlint generated Kotlin (requires brew install ktlint)
```

### Tests are part of the change, not a follow-up

New behaviour ships with a test unless the change is small enough that a test
would only restate it — a rename, a doc string, a formatting pass. "I'll add
coverage later" is how the untested paths in this repo got there.

The bar is not coverage percentage, it is: **would this test fail if the fix
were reverted?** Check by reverting it. A test that passes either way is worse
than none, because it is claimed as evidence. More than one fix here shipped
with a test that could not fail — including a headline fix whose entire clause
could be deleted with the full suite still green.

### Decision log — check both directions

Before committing, ask two questions, not one.

**Does this need a new record?** Anything non-obvious: a tradeoff, a workaround,
a convention, a "why X and not Y". The test is whether a reader six months from
now would ask why it is like this. If the commit message is explaining a
decision, that decision belongs in `decisions/` where it is findable, not only
in `git log`. Record it in the same commit, not as a follow-up.

**Does this INVALIDATE an existing record?** This is the half that gets missed,
and it is the more dangerous one. A record asserting a property the code no
longer has is worse than no record: it is a claim a maintainer will act on.
Grep `decisions/` for the mechanism you are changing before you commit.

Both failed in one session, on the same change:

* A decision record claimed "the frame-registry generation is untouched because
  the parked slot stops re-registering once it stops laying out." It reasoned
  about the outgoing direction only. The returning direction was broken —
  silently, for exactly the screens the change optimised for — and the record
  said it was fine.
* Source comments elsewhere stated invariants the same change inverted:
  `MobLazyList`'s latch reasoned that "only navigation changes the container's
  identity", which had just stopped being true.

When you correct a record, correct it **in place** with a note saying what was
wrong, rather than quietly deleting the claim. The wrong version is the part a
future reader needs to recognise, and `decisions/` is append-only for
superseding whole decisions, not for silently editing away a mistake inside one.

### Adversarial review — before the commit, by a subagent

**Non-trivial work gets an adversarial review before it is committed.** Spawn a
subagent, point it at the actual diff, and tell it to find defects rather than
to approve. Act on what it finds, then commit.

It must be a **separate agent**, not a re-read of your own work. The thing that
is wrong is usually the author's mental model of the change, and that model is
exactly what a self-review carries into the second pass.

Give the reviewer: the diff to read (`git diff <base>..HEAD`, and the base
explicitly, since a diverged local branch will otherwise sweep in the whole
tree), what the change claims to do, and the specific things you are least sure
about. Tell it to cite `file:line` for every finding, to rank them
blocking / should-fix / nitpick, and to separate what it verified in source from
what it is reasoning about platform semantics. Ask it to say plainly if the
change is sound rather than inventing problems — but only after it has looked
hard.

**Skip it for** mechanical or trivial changes: formatting, a typo, a version
bump, a changelog edit, moving a file. Reach for it when the change has
behaviour, touches native code, or spans a platform boundary.

This is not ceremony. In one session, pre-commit reviews caught the following
in `mob` — the examples are from there because that is where the session ran,
and the bug classes are the ones these templates generate — each of which would
otherwise have shipped:

* a helper defined inside `#if !MOB_RELEASE` but called unconditionally from
  Swift, which linked in debug and would have failed **every iOS release
  build**;
* a cache whose tests asserted the write path and nothing about the read, so
  deleting the lookup, or reading under a constant key, passed the whole suite;
* a fix that covered 3 of 7 call sites on one platform while claiming parity
  with the other;
* a comment and a decision record asserting a race was closed when the code
  only narrowed it;
* generated source telling every user that a feature does nothing, in the
  release that made it work.

The one substantial change that skipped review that session was the largest one
in the batch. Do not let size be the reason to skip.

### Before the merge — a second review, on the PR

The pre-commit review reads a diff. This one reads a diff **that claims to be
finished**, against a master that has moved since you started. Those are
different questions, and the second one has caught more.

Both frame-timing PRs in one session passed pre-commit review. The pre-merge
review then found that one of them shipped its headline fix untested — it
deleted the conversion and all 1545 tests still passed — and blocked the other
outright over per-widget state that navigation had silently stopped resetting.
Neither was visible in the diff alone; both needed someone asking "is this
actually done, and does it still fit?"

Give the reviewer the PR, what it claims, and what you are least sure of, and
ask for a verdict — MERGE or DO NOT MERGE, with reasons. Then act on it. A
review you overrule is fine if you say why; a review you skip because the work
felt done is the case this exists for.

**Check the mechanical preconditions yourself; do not delegate them:**

- **CI is green AND the run is newer than the last commit.** A green check from
  before your latest push proves nothing. One PR here carried a month-old green
  run from 40 commits of master ago.
- **The branch is not behind master.** The `pre-push` hook says how far.
- **Cross-repo claims are true now, not eventually.** Documentation that names
  a sibling's version — "requires mob_new 0.4.32" — is false until that version
  exists. Land the sibling first, or make the claim true in the same session.
- **Stacked PRs merge base-first**, and the child gets retargeted and re-checked
  after the base lands.

### Trust the instrument last

Every rung of the fidelity ladder assumes the thing measuring is honest. When it
is not, the failure does not look like an error — it looks like a result.

Two from one session, both of which were believed for a while:

* A navigation benchmark reported a 6.5x improvement. The tree was installed by
  a `LaunchedEffect`, which runs *after* composition, so the frame being timed
  still showed the old screen. The real figure was about half that, and the
  published numbers had to be retracted.
* An on-device check printed `PASS` against a build that had failed to compile,
  because the deploy before it had failed and the previous build was still
  installed. The screen it claimed proved the fix had never scrolled.

So:

- **A number better than the theory allows is a bug in the measurement.**
  Navigation cannot be cheaper than re-rendering the same tree. When the result
  is too good, go and find out why before reporting it.
- **Make a probe fail loudly when its own precondition does not hold.** A check
  that silently passes when the setup did not happen is worse than no check.
- **Corroborate against something you did not build.** Platform counters,
  `Davey!` frame reports, `Skipped N frames`, a screenshot. Agreement within
  30% of an independent source is evidence; your own instrument agreeing with
  itself is not.
- **When you publish a number that turns out wrong, retract it in place** and
  say what was wrong. Someone will otherwise act on it.

## Issue tracking — status lives in Linear

Status lives in **Linear** (team `MOB`), which is the single board across `mob`,
`mob_dev` and `mob_new` — see `mob/AGENTS.md` for the full split of
responsibilities. The short version, because work in this repo routinely starts
from an issue filed against another one:

- **Linear (`MOB`)** — live status and worklist. One issue per thread.
- **`decisions/`** — durable rationale. Link it from the issue; don't copy it in.
- **PRs / git** — the code. Reference the issue id.

Keep the issue current as you go, not at the end. An issue that says what was
tried and ruled out is worth more than one that says "done" — most of what this
project has learned lives in the ruled-out half.

## Release flow

Canonical process lives in
[`mob/RELEASE.md`](https://github.com/GenericJam/mob/blob/master/RELEASE.md)
— trigger model (mix.exs as source of truth), patch-bump default with
mandatory permission, CHANGELOG conventions, per-step idempotency of
`release.yml`.

> **Review gate is on by default.** Everything that landed since the
> last published version gets a code review *before* you publish —
> scoped at `v<last-published>..HEAD`, not per-PR — plus the
> version-sanity checks (is this version already published? did
> anything merge after the bump commit?). Skip only if the user says
> so. See RELEASE.md → "Review gate".
>
> `mob_new` ships in lockstep with `mob` for anything spanning a
> runtime change and its generator template: publishing one without
> the other leaves generated apps mismatched against the library they
> depend on. Check both before cutting either.

**mob_new specifics:**

- The published Hex package is the project generator itself; new
  apps built via `mix mob.new` from a fresh install pick up the
  latest published template the moment a version lands.

**Pre-push hook**: `.githooks/pre-push` runs `mix format
--check-formatted`, `mix credo --strict`, `mix compile
--warnings-as-errors` on every push (fast). When the push touches
`mix.exs` it additionally runs the full test suite as the release
preflight. Activate once per clone or worktree:

```bash
git config core.hooksPath .githooks
```

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

- **`--deliver` output is gated so default output stays byte-identical.**
  `mobile/` (mob_deliver expansion screens) is skipped by
  `deliver_excluded?/3` on BOTH render paths (native and LiveView) unless
  `deliver: true`; `mobile/` must never enter `elixirc_paths`, or the
  expansion screens compile into the binary. The Ed25519 publish key is made
  once in `generate/3` (`with_deliver_key/1`) so the public key in
  `config.exs.eex` matches `mob_deliver_signing.key`. Keep EEx conditionals
  glued to the neighbouring line (`...Repo<%= if deliver do %>` …
  `<% end %>`): a conditional on its own line leaves a blank line in every
  project generated without the flag. Publish output goes to
  `mob_deliver_publish/`, not `priv/`, because mob_dev bundles all of `priv/`.

- **Native apps ship showcase plugins by default (0.4.2).** `mix.exs.eex`
  depends on `mob_camera` / `mob_location` / `mob_biometric` / `mob_themes`,
  and `mob.exs.eex` activates them (`config :mob, :plugins` / `:styles` /
  `:default_style`). The home screen does NOT hardcode their nav entries —
  it enumerates `Mob.Plugins.screens/0` and renders a button per
  manifest-declared demo screen, so adding/removing a plugin needs no home
  edit. These are native-only: the activation lives in `mob.exs.eex` (the LV
  path overwrites mob.exs via `LiveViewPatcher.mob_exs_content/0` and uses
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
  (`LocalSlotEpoch`); do not fold the two together. A text field adopts a
  pushed value only through `MobTextSync`, which ignores echoes of what the
  field itself sent (MOB-309); one with no `value` prop ignores renders.

- **Every resource the manifest / Info.plist names must ship in
  `priv/static/`.** `android:icon="@mipmap/ic_launcher"` with no
  `res/mipmap-*/ic_launcher.png` fails AAPT on the first native build
  (MOB-106). The default icon is legacy PNGs only — no
  `mipmap-anydpi-v26/` adaptive XML, because on API 26+ that XML wins over
  the PNGs and a plain `mix mob.icon` (which rewrites only the PNGs) would no
  longer change the visible icon. iOS ships a single-size 1024 `AppIcon`;
  `mix mob.icon` rewrites the whole set. See
  `decisions/2026-09-30-default-launcher-icon-in-template.md`.

- **MainActivity stays `singleTop`; deep links opt into `singleTask`
  (MOB-379).** Under `singleTop` a VIEW intent from another app's task (a QR
  scanner, a browser that doesn't add `FLAG_ACTIVITY_NEW_TASK`) starts a
  second MainActivity in that task, composing against the one MobBridge/BEAM,
  so an app with `url_schemes` needs `singleTask` (mob_dev refuses to build
  without it). It isn't the template default: a launcher-icon start that
  reuses the task clears everything above a `singleTask` activity, so every
  return through the icon would close an open picker, share target or
  scanner, in every app. See
  `decisions/2026-10-03-deep-links-need-single-task.md`.

- **Deep links go through `deliverLink`, inside the no-replay guard
  (MOB-379).** MainActivity forwards a VIEW intent's URI (not `content:` /
  `file:`, which are documents) to `MobBridge.nativeDeliverLink` →
  `mob_deliver_link` from `onCreate`'s `savedInstanceState == null` /
  not-from-Recents guard and from `onNewIntent`, exactly like notification
  taps; outside the guard a re-created activity replays the link. iOS does the
  same from the SceneDelegate (`connectionOptions.URLContexts` and
  `scene:openURLContexts:`). The template declares no intent-filter or
  `CFBundleURLTypes`: mob_dev injects them from `url_schemes` in mob.exs.

## The default app is the Mishka Chelekom showcase (via the mob_mishka plugin)

The Mishka composites are no longer vendored into the template
(`priv/templates/mob.new/lib/app_name/components/mishka_*.ex.eex` deleted
in MOB-252). They ship as the `:mob_mishka` Hex plugin, which the
generated `mix.exs` depends on. The plugin's `on_start` registers each
`<Mishka…>` tag via `Mob.Composite`; the plugin's `priv/mob_plugin.exs`
whitelists them for `~MOB` via MOB-247's plugin-manifest tag discovery.

What still lives here in `priv/templates/mob.new/lib/app_name/`:

- `showcase/` — the gallery pages that USE the plugin's composites via
  `<Mishka…>` tags in `~MOB` sigils, plus the `showcase.ex` registry.
- `theme_bar.ex.eex` — the theme picker.
- `showcase_test.exs.eex` — the gallery test.

These files alias `MobMishka.Components.Mishka*` for the few sites that
need to reference a composite by module. If a user runs
`mix mob_mishka.gen <name>` to eject a composite into their `lib/`, the
plugin's registry picks up the app-local override on next boot (via
`config :mob_mishka, :override_namespace, <App>.Components`).

`home_screen.ex.eex`, `app.ex.eex` and `home_screen_test.exs.eex` are
hand-maintained and carry the `--blank` gating as two whole modules in
one file rather than interleaved fragments; `blank_excluded?/3` keeps
the showcase tree out of a blank app.

Verifying a template change against a real project from a worktree needs three
env vars: `--local` resolves templates from `$HOME/code/mob_new` unless
`MOB_NEW_DIR` points at the worktree, and `MOB_DIR` / `MOB_DEV_DIR` must name
the local mob checkouts. The globally installed `mob_new` archive shadows the
repo task, so run with `MIX_ARCHIVES` set to a temp dir that contains only a
copy of the `hex-*` archive (an empty dir also hides Hex).

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

### Multi-Android — node naming (FIXED 2026-05-28 in mob_dev, commit `7497f4b`)

`mob_dev` derives the Android dist node-name suffix from the device
**serial** (matching what `Mob.Dist` registers), not the IP. Two emulators
get distinct suffixes (`emulator_5554` / `emulator_5556`) and no longer
collide in EPMD. See `mob_dev/decisions/2026-05-28-android-node-name-by-serial.md`.

### Dist ports are serial-derived (mob_dev 0.6.7+)

Ports are no longer assigned by per-run index, which made every project's
first device claim 9100 and collide in the shared Mac EPMD. Each device
gets a stable port from its serial / UDID (`MobDev.Tunnel.serial_base_port/1`,
`9100..9899`) and listens on it device-side, so `adb forward` is 1:1 and
matches what EPMD advertises. If `mix mob.connect` fails it reports why
(app not running, dist not registered, port mismatch, no forward, cookie
mismatch). To inspect by hand:

```bash
epmd -names           # registered nodes + their ports
adb forward --list    # host→device forwards (should be 1:1, no dupes)
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

## Decision log

Non-obvious decisions — tradeoffs, workarounds, conventions, "why we chose X
over Y" — go in `decisions/`, **one file per decision**:

    decisions/YYYY-MM-DD-short-slug.md

Each file is a lightweight ADR:

    # <Title>
    - Date: YYYY-MM-DD
    - Status: accepted | superseded by <file> | proposed
    ## Context        — what prompted this
    ## Decision       — what we chose
    ## Consequences   — tradeoffs, follow-ups

**Append new files; never edit existing ones.** If a decision changes, add a
new file and mark the old one `Status: superseded by <new-file>`. One file per
decision keeps the log conflict-free across parallel agents/worktrees — the
date-sorted directory listing is the index. Record a decision the moment you
make a non-obvious call, not later.

## Keep this file up to date

When you change template structure (add, move or remove a template path),
change the LV phx-owned blocklist, or hit a new generator gotcha — update this
file in the same commit, not as a follow-up.
