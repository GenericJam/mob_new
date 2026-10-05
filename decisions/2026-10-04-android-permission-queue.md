# Android permission requests go through a queue, one dialog at a time

- Date: 2026-10-04
- Status: accepted

## Context

MOB-391. Operator asks for `:notifications` on the first chat send; seconds
later its agent's location tool asks for `:location`. On a Moto G 2024
(Android 15) the location request came back `:denied` and the user never saw a
location dialog.

`Activity.requestPermissions` allows one request per activity at a time. A
second call while a dialog is up logs `Can request only one set of permissions
at a time` and calls `onRequestPermissionsResult` straight away with empty
arrays. The generated `MainActivity` read empty results as `granted = false`,
and `MobBridge` kept a single `pendingPermissionPid` / `pendingPermissionCap`
slot that the second request had already overwritten. So the second requester
got `:denied` at once, and the first dialog's answer then went to the second
requester under the second capability. Reproduced on an Android 15 emulator:
`{:permission, :location, :denied}` with no dialog shown, then the user's
"Allow" on the notifications dialog arrived as
`{:permission, :location, :granted}`; no `:notifications` answer at all.

Separately, `:location` maps to FINE + COARSE (mob_location's provider) and
the result required every permission granted. On Android 12+ that request
offers "Approximate", which grants COARSE only, so choosing it reported
`:denied`.

## Decision

`MobPermissionQueue` (a plain Kotlin class, no Android types beyond the
permission name constants) owns permission requests:

- Requests queue and go to the system one at a time, each with its own request
  code from a 64-code band starting at 9001. Each is answered once, to its own
  pid and capability.
- A result is matched to the request in flight by its code; any other code is
  ignored. An empty result for the request in flight (cancelled or interrupted)
  answers from the current permission state rather than as `:denied`.
- A request that is already satisfied is answered `:granted` at once, even
  while another request's dialog is up, and is re-checked when it reaches the
  head of the queue (an earlier dialog may have granted it).
- `ACCESS_FINE_LOCATION` is satisfied by `ACCESS_COARSE_LOCATION`. Every other
  permission in a capability must be granted itself.
- No activity, or only a finishing/destroyed one, or nothing left to ask
  (below API 33 androidx drops POST_NOTIFICATIONS from the request and returns
  without a callback): `:denied`, and the queue moves on.

`MobBridge.request_permission` hops to the main thread before touching the
queue; the NIF calls it from a BEAM scheduler thread. `MainActivity` forwards
every `onRequestPermissionsResult` unchanged.

The queue is a separate file so its behaviour is unit-tested on the JVM
(`MobPermissionQueueTest.kt`, in the generated project's `test` source set),
with a fake platform that answers a second request with empty results the way
Android does.

## Consequences

- The `{:permission, cap, :granted | :denied}` contract is unchanged; Mob
  apps see more `:granted` (Approximate) and no false `:denied`.
- `:location` granted no longer means precise location. An app that needs
  precise location has to check for it itself; the message carries no
  precision. Because a held COARSE answers `:location` at once, asking again
  after the user chose Approximate does not bring up Android's "change to
  precise" dialog, and Mob has no other way to ask for it. That is
  deliberate: Operator asks for `:location` on every location tool call, and
  an upgrade prompt each time would be worse. Revisit if an app needs precise
  location.
- A request whose result never comes back would hold up the requests behind
  it. Android keeps an in-flight permission request across activity
  re-creation and delivers its result to the new activity. The bridge does not
  launch from a finishing or destroyed activity, nor a request androidx would
  drop without a callback (above). The remaining way to lose a result is
  process death, which clears the queue anyway. There is deliberately no
  timeout: a user can leave a dialog up for as long as they like.
- Existing apps have to port the change by hand (new file plus edits to
  `MobBridge.kt` and `MainActivity.kt`); see the CHANGELOG's Upgrading note.
