# Android sends throttle config on every composition

- Date: 2026-09-03
- Status: accepted
- Implements: MOB-134 (Android half), part of MOB-124
- Pairs with: `mob/decisions/2026-09-02-throttle-config-targets-the-building-table.md`

## Context

`Mob.Renderer` emits a sibling config prop next to each high-frequency handler
— `scroll_config` beside `on_scroll`, `drag_config` beside `on_drag`, built by
`Mob.Event.Throttle`. iOS reads them. **Nothing on Android did.**
`mob_set_throttle_config` was exported from `mob_nif.zig` and declared in
`mob_beam.h`, and had no caller anywhere in the Kotlin bridge, so an app asking
for `throttle: 100, delta: 8` silently ran at the compiled-in default. Same
"declared, carried on the wire, silently ignored" shape as MOB-138 — and only
reachable at all once MOB-138 wired `on_scroll`/`on_drag` in the first place.

## Decision

Read the config prop and forward it from a `SideEffect`:

```kotlin
@Composable
private fun ApplyThrottleConfig(props: Map<String, Any?>, handle: Int?, configKey: String) {
    if (handle == null) return
    val cfg = props[configKey] as? JSONObject ?: return
    SideEffect { MobBridge.nativeSetThrottleConfig(handle, ...) }
}
```

Two details carry the whole design.

**It must run on every composition, not once.** `clear_taps` runs at the top of
every frame and zeroes the per-handle throttle state — `throttle_ms`,
`delta_threshold`, `last_emit_ns`, `seq` — because table slots are reused across
renders. Each render also re-registers the handler under a **new** handle. A
`LaunchedEffect` keyed on anything stable would configure one frame and leave
every later frame running on defaults. `SideEffect` runs after every successful
composition, which is exactly that cadence.

**Resolving against the ACTIVE table is correct here, unlike iOS.** Android's
table swap happens inside `nif_set_root`, before the JSON is handed to the UI
thread, so by the time Kotlin composes, the handles in this tree are already
active. iOS applies config from inside its deserialiser, *before* its swap,
which is why it needed a build-table lookup instead. Same bug on paper, opposite
fix — worth stating because the obvious move is to mirror the iOS change.

An absent `leading`/`trailing` maps to 1, not 0, because `Mob.Event.Throttle`
defaults both to true. Note what that does **not** claim: neither field has a
native reader — `mob_set_throttle_config` stores them and `throttleCheck` never
consults them — so the mapping is for whoever implements them, not behaviour in
force today. The same is true of `debounce_ms`: it is carried, stored, and
unread on both platforms. **This change makes `throttle` and `delta` work; it
does not make `debounce` work.**

## Consequences

Verified on the Pixel 8 emulator with two scroll nodes on one screen, one
default and one `throttle: 500, delta: 1`, comparable swipes:

```
default 33ms       21 events
configured 500ms    4 events
```

Before the change both ran at the default.

The measurement only works if the handler is **not** delivered to the screen
process. `Mob.Screen.Server.forward/2` repaints unconditionally after every
`handle_info`, and every repaint calls `clear_taps`, which zeroes
`last_emit_ns`; `throttleCheck` then treats the next sample as "no previous
emission" and emits regardless. A scroll handler on the screen defeats its own
throttle. The test screen routes events to a plain process for that reason, and
the underlying problem is recorded on MOB-124 rather than worked around here.
