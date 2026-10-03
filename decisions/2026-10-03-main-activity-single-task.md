# MainActivity is singleTask, for deep links

- Date: 2026-10-03
- Status: accepted (MOB-379)

## Context

Deep links reach Android as VIEW intents, often from another app's task: a
QR scanner, or a browser that doesn't add `FLAG_ACTIVITY_NEW_TASK`. Under
`singleTop` such an intent creates a new MainActivity in the sender's task.
The BEAM and `MobBridge`'s registries are process-wide, so two activities
would compose against one bridge; the template already guards against a
relaunched activity reusing a disposed composition's state, and a second
live one is worse.

## Decision

`android:launchMode="singleTask"`. Every intent for MainActivity reaches the
one instance's `onNewIntent`, which forwards notification taps and links.

## Consequences

- An intent that reaches the existing instance finishes the activities
  stacked above it in its task: an in-app picker or scanner left open is
  closed when a link or notification tap arrives. Plugins that need a
  result from such an activity lose it in that case.
- The mob_dev-injected deep-link intent-filter (from `url_schemes` in
  mob.exs) can be exported safely without a second instance appearing in a
  foreign task.
- Existing apps keep `singleTop` until they change their manifest; the
  CHANGELOG upgrade note says so.
