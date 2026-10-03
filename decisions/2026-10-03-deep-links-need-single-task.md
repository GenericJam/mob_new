# Deep links need a singleTask MainActivity; the template stays singleTop

- Date: 2026-10-03
- Status: accepted (MOB-379)

## Context

Deep links reach Android as VIEW intents, often from another app's task: a
QR scanner, or a browser that doesn't add `FLAG_ACTIVITY_NEW_TASK`. Under
`singleTop` such an intent starts a new MainActivity in the sender's task.
The BEAM and `MobBridge`'s registries are process-wide, so two activities
would compose against one bridge; the template already guards against a
relaunched activity reusing a disposed composition's state, and a second
live one is worse. `singleTask` routes the intent to the one instance's
`onNewIntent`.

The first MOB-379 commit made the template `singleTask` for every app. Review
reversed that before it merged: when a launcher-icon start reuses the task,
AOSP's `ActivityStarter.recycleTask` → `complyActivityFlags` runs
`performClearTop` for a `singleTask` activity. Every return through the app
icon would finish whatever is stacked above MainActivity (a file picker, a
share target, a scanner), in every generated app, including apps that never
use deep links.

## Decision

- The template keeps `android:launchMode="singleTop"`.
- Deep links are opt-in. An app that sets `config :mob_dev, url_schemes: [...]`
  also sets `singleTask` on MainActivity. mob_dev 0.7.12 refuses to build
  `url_schemes` when the launcher activity is neither `singleTask` nor
  `singleInstance`, and both the manifest and the mob.exs `url_schemes`
  comment say so.
- `deliverLink` stays in every MainActivity, so deep-link apps have no code
  to port. It is not inert without an intent-filter: MainActivity is exported,
  and an intent addressed to it explicitly (another app, or
  `adb shell am start -n <pkg>/.MainActivity -a android.intent.action.VIEW -d x://y`)
  skips filter matching, so any app can still hand it a `{:link, ...}`. A
  screen with its own `handle_info/2` clauses and no catch-all crashes on one
  and is restarted by the router, as with any unexpected message. That
  exposure is the same as an exported activity's for any other extra; gating
  the forward on `queryIntentActivities` was rejected as more code than the
  risk warrants.

## Consequences

- An app without deep links keeps its activity stack on a launcher return.
- A deep-link app accepts the clear-top on a launcher return and when a link
  reaches the running instance. That trade-off is the app's choice, made
  where it sets `url_schemes`.
- The rule is stated in the generated manifest's comment, in both mob.exs
  `url_schemes` comments (native and LiveView), and in mob_dev's check; the
  check is the one that can't be missed.
