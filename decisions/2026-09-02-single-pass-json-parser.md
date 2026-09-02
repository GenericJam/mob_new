# Android parses the render payload in one pass

- Date: 2026-09-02
- Status: accepted
- Implements: MOB-137, part of MOB-124
- Builds on: `2026-09-02-lazy-scroll-on-android.md`

## Context

After MOB-128 took the Android main thread down, `set_root` was the largest
remaining block in the render pipeline. It went through
`JSONObject(json).toMobNode()`, which materialises the same payload three times:

1. an `org.json` tree — a `LinkedHashMap` per node, a `String` per key and per
   value, every number boxed,
2. a second `mutableMapOf` copy of every props map inside `toMobNode`,
3. the `MobNode` itself, plus an `ArrayList` per node.

## Decision

`MobJson.parseNode` walks the wire text once and emits `MobNode`s directly. No
intermediate tree, no second copy.

### The contract that shapes it

`MobBridge` reads props by runtime type — `as? String`, `as? Number`,
`is JSONArray`, `is JSONObject`. A value of the wrong type does not crash; it
reads as null and the prop silently stops working. So the bar is not "parses
JSON", it is **indistinguishable from what org.json produced**:

- integrals are `Int`, or `Long` when they do not fit — JSONTokener's ordering
- reals are `Double`
- **nested objects and arrays inside props are still real `JSONObject` /
  `JSONArray`**, because `tabs`, `uniforms`, `detents` and the `*_config`
  throttle maps are read as exactly those. They are rare enough that building
  them properly costs nothing against the per-node work this avoids.
- a JSON null in props is `JSONObject.NULL`, **not** Kotlin null

That last one is the subtle one, and it was found by a test rather than by
reading. `JSONObject.NULL.equals(null)` returns **true**, so `props["k"] == null`
behaves the same for both — but `props["k"]?.let { }` runs for the sentinel and
not for a real null. The first version of this parser stored Kotlin null and the
differential test passed anyway, because the comparator's own `expected == null`
short-circuit was fooled by the same equals. Pinning the *oracle's* behaviour in
its own test is what exposed it; the comparator now uses identity.

## Results

Measured on a Moto G Power with a 148 KB payload, each parser alone in its own
build, steady state (the first third of samples discarded):

| | p50 | min | mean |
|---|---|---|---|
| `JSONObject().toMobNode()` | 26083 µs | 25075 µs | 39307 µs |
| `MobJson.parseNode` | **18204 µs** | **17782 µs** | 22400 µs |

**1.43x** — about 8 ms per frame on a dense screen.

### Two things worth recording about how that was measured

**Do not trust an in-process A/B here.** Running both parsers back to back in
the same frame gave 2.08x when the old path ran first and 1.19x when MobJson
did. Whichever runs second benefits from a warm cache, and the effect is larger
than the difference being measured. Only separate builds give an honest number.

**The number this issue was opened with was cold.** MOB-137 quoted 82 ms for
this stage (50 ms org.json + 32 ms conversion), measured shortly after launch.
Steady state is 26 ms. The direction was right and the split was right, but the
magnitude was a warm-up artefact, and it is why the estimate of 3-5x was wrong.

## Consequences

- A hand-written parser is code we now own: escapes, `\u` sequences, number
  forms, malformed input. It ships with 15 JVM unit tests — a differential
  comparison against the old path over a representative tree and over every
  escape form, plus targeted tests for number typing, the container contract,
  the NULL sentinel, deep nesting, structural characters inside strings, and
  twelve malformed inputs.
- Those tests need a real `org.json` on the unit-test classpath, because the
  Android SDK jar stubs it out — every method throws. The Maven artifact is a
  fair oracle for structure and strings but **diverges on numbers**: it returns
  `BigDecimal` for reals where Android's AOSP implementation returns `Double`.
  MobJson matches Android, so the comparator normalises the oracle rather than
  the parser, and the authoritative number-typing expectations are asserted
  against MobJson directly.
- `NewStringUTF` is untouched. It costs 2 ms of this stage — an earlier plan
  named it as a target, and it is not one.
