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

**How reachable this is.** A *bare* generated app declares only
`UIBackgroundModes: audio` and has no
`didReceiveRemoteNotification:fetchCompletionHandler:` or
`performFetchWithCompletionHandler:`, so most of the listed launches cannot
occur in one: background push needs `remote-notification`, fetch needs `fetch`,
and iOS does not relaunch a terminated app to resume audio.

Two do reach real apps. `mob_bluetooth`'s manifest array-merges
`bluetooth-central` / `bluetooth-peripheral` into the host `Info.plist` whenever
an app sets `config :mob_bluetooth, ble_background_modes: [...]`, which enables
CoreBluetooth state-restoration launches in a shipped, supported configuration.
And **prewarming needs nothing declared at all** — iOS 15+ prewarms
scene-based apps routinely, calling `didFinishLaunchingWithOptions:` with no
scene. So this is less latent than the first draft of this record claimed.

## Decision

`application:didFinishLaunchingWithOptions:` boots the runtime, unconditionally.

**Two wrong turns on the way there, both worth recording.**

Booting there unconditionally *was* the first attempt, and the pre-commit review
rejected it: `didFinishLaunchingWithOptions:` always runs before any scene
connects, so the BEAM would start before a window exists. `Mob.Screen` reads the
safe-area insets during `init`, mob's `nif_safe_area` located them via
`connectedScenes` and returned zeros when there was no window, and
`ensure_safe_area/3` only recomputed when the key was absent — so the first
reading was kept for the screen's lifetime and the root screen could spend it
laid out under the notch.

The second attempt gated the boot on
`applicationState == UIApplicationStateBackground`, reasoning that this
identified "a launch with no scene coming". The pre-merge review showed it does
not. That state means **background launch or prewarm**, and for a scene-based
app — which every generated app is — an iOS 15+ prewarm calls this exact method
and creates no scene. So the gate fired on prewarmed launches and reintroduced
the very race it was written to prevent, with the timing skewed *worse*: the
BEAM gets a head start of seconds to minutes before the user taps. There is no
reliable discriminator available here (`ActivePrewarm` is reported gone on
iOS 16+). "A background launch never connects a window scene" was also simply
false — it connects one later, when the user opens the app.

The conclusion is that **boot order must not be load-bearing**. That is fixed in
mob (`2026-09-10-a-safe-area-read-with-no-window-is-not-an-answer.md`):
`nif_safe_area` reports `:no_window` distinctly and the screen refuses to cache
it. With the reading self-healing, every boot order is safe and this method can
boot unconditionally — the simplest version, correct for the right reason rather
than by luck.

The `dispatch_once_t` moves into a shared function, `mob_boot_runtime()`,
because both entry points can call it and a second `erl_start` in one process is
fatal. It is a *function-local static* inside a file-scope function — one
instance shared across every call — not a file-scope variable.

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
