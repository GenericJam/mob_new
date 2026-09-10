# A background launch boots the BEAM too

Date: 2026-09-10
Status: accepted
Ticket: MOB-166
Amends: 2026-08-25-uiscene-lifecycle-xcode27.md

## Context

Xcode 27 requires scene-based startup, so the MOB-97 port moved window creation
out of `application:didFinishLaunchingWithOptions:` into
`scene:willConnectToSession:`. The BEAM boot moved with it, because it lived in
the same method.

That coupled the runtime's existence to a window scene connecting. A launch that
never connects one — a background launch — would never start the BEAM at all.

**What this is not.** The first draft of this record justified the change with a
push-token example: `didRegisterForRemoteNotificationsWithDeviceToken:` calling
`mob_send_push_token` into a dead runtime. That cannot happen, twice over. APNs
only calls that delegate method after the app calls
`registerForRemoteNotifications`, and mob's only caller of that is a NIF in
`mob_notify` — which cannot run before the BEAM. And `mob_send_push_token`
already returns early when no delegate is registered. The example was invented,
and it is recorded here rather than quietly dropped because it was the stated
reason for the change.

**What is also not true today.** Generated apps declare only
`UIBackgroundModes: audio`, and have no
`didReceiveRemoteNotification:fetchCompletionHandler:` or
`performFetchWithCompletionHandler:`. So none of the launches this fixes can
currently occur in a generated app: background push needs `remote-notification`,
background fetch needs `fetch`, BLE restoration needs the bluetooth modes, and
iOS does not relaunch a terminated app to resume audio. This is a latent trap
being closed before it can bite, not a live bug being fixed — and closing it is
worth doing precisely because the failure mode is silence.

## Decision

`application:didFinishLaunchingWithOptions:` boots the runtime **when
`applicationState == UIApplicationStateBackground`**, and only then.

The gate is the whole design, not a detail. Booting unconditionally there was
the first attempt and it was a regression on the path every user takes:
`didFinishLaunchingWithOptions:` always runs before any scene connects, so the
BEAM would start before a window exists. `Mob.Screen` reads the safe-area insets
during `init`, mob's `nif_safe_area` locates them via `connectedScenes` and
returns zeros when there is no window, and `Mob.Screen.Server.ensure_safe_area/3`
only recomputes when the key is absent — so the first reading is cached for the
screen's lifetime. Lose that race once and the root screen renders under the
notch and home indicator until it is replaced. UIKit would usually win, which is
what makes it the bad kind of bug.

Gating on `applicationState` distinguishes the two cases at the one point where
the answer is knowable: `Background` for a launch with no scene coming,
`Inactive` for an ordinary foreground launch. Foreground ordering is therefore
byte-for-byte what it was.

The `dispatch_once_t` moves into a shared file-scope function,
`mob_boot_runtime()`, because both entry points can call it and a second
`erl_start` in one process is fatal. Note this is a *function-local static*
inside a file-scope function — one instance shared across all calls — not a
file-scope variable.

## Consequences

- iOS files are app-owned. Existing apps need `ios/AppDelegate.m` regenerated or
  hand-ported, as MOB-97 tracked.
- The generator test extracts each function body by brace matching, with
  comments stripped, and asserts inside it. The first version split on "the next
  method-looking line", which ran past the closing brace into the following
  method's doc comment — so deleting the boot call and naming
  `mob_boot_runtime()` in that comment passed the test named after that exact
  regression. Four mutations are now checked: boot deleted, guard removed from
  the shared function, shared function emptied, and the background gate removed.
  All four fail; correct code with an unrelated `dispatch_once` elsewhere in the
  file still passes.
- Verified on a simulator by generating an app from these templates, building
  native, and confirming over dist that the full runtime came up with the UI
  rendered. That verification could not have caught the safe-area regression:
  the device was an iPad, which has no notch, so zero insets look correct. The
  device check that would have caught it is a notched iPhone.
- **Not verified: an actual background launch.** That needs a background mode
  declared and a real trigger, neither of which a generated app has. The
  argument that it works is structural — `didFinishLaunchingWithOptions:` runs
  on every launch and reports `Background` for these — not observed.
- Follow-ups filed rather than folded in: iOS never calls
  `mob_set_launch_notification_json` or `mob_handle_opened_url`, both of which
  `mob_beam.h` documents for this very method, while Android does the equivalent
  in `MainActivity` — so a cold launch from a notification tap drops its payload
  on iOS only.
- Android boots the BEAM in `MainActivity.onCreate` and its only manifest
  receiver is BEAM-free by design, so it does not have this bug.
