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
  forms, malformed input. It ships with 19 JVM unit tests — a differential
  comparison against the old path over a representative tree and over every
  escape form, plus targeted tests for number typing, the container contract,
  the NULL sentinel, deep nesting, structural characters inside strings, and
  twelve malformed inputs, whitespace forms, duplicate keys and prop order.
- Those tests need a real `org.json` on the unit-test classpath, because the
  Android SDK jar stubs it out — every method throws. The Maven artifact is a
  fair oracle for structure and strings but **diverges on numbers**: it returns
  `BigDecimal` for reals where Android's AOSP implementation returns `Double`.
  MobJson matches Android, so the comparator normalises the oracle rather than
  the parser, and the authoritative number-typing expectations are asserted
  against MobJson directly.
- `NewStringUTF` is untouched. It costs 2 ms of this stage — an earlier plan
  named it as a target, and it is not one.

## Verification, after adversarial review

The review built a **faithful oracle** rather than trusting the Maven artifact:
it vendored the real AOSP `org.json` out of the Android SDK sources and ran
against both. Against that it found **no correctness bug**:

- 40,000 fuzzed node trees (22 MB of JSON) compared against both oracles on node
  type, prop key set, prop **insertion order**, every value's **runtime class**
  and container contents — no divergence.
- 300,000 byte-level mutants and 413 truncation prefixes — zero non-`JSONException`
  outcomes. No `StringIndexOutOfBoundsException`, no hang.
- Stack depth is not a regression: `StackOverflowError` at ~1664 children deep
  vs org.json's ~1158, and the skipped-key path is iterative where org.json blows
  at 5269.

It did find four things, all fixed here.

**A performance regression I introduced.** The escaped-string path appended
character by character, where AOSP's `nextString` bulk-copies each run between
escapes. An escape near the front of a 400 KB string was **1.85x slower than the
org.json this replaces** (694 µs vs 375 µs), and even escape-every-10-characters
was slower. Now bulk-appends runs.

**The compatibility claim was broader than the evidence.** The KDoc said
"throws JSONException, as `JSONObject(String)` did". Against real AOSP that is
false for about twenty input shapes — this reader is stricter (invalid escapes,
trailing content, unparseable numbers, comments, unquoted keys) and, in one
place, more lenient (a missing `type`). Documented explicitly now, including the
three inputs that parse on both sides with different answers (`010` is octal to
AOSP; `09` is a `Double` there and an `Int` here — a runtime class change; `1e400`
throws there and yields infinity here). None is emitted by Elixir's JSON encoder.

**A shipped test pinned a divergence without saying so.** It asserted `\q`
throws, which is true of MobJson and **false of Android**, where it yields `"q"`.
The Maven oracle throws, so the test passed for the wrong reason. Now labelled.

**Mutation testing found four gaps**, all closed and each re-verified to fail
when its behaviour is broken: whitespace other than a space, the NULL sentinel
inside a nested *array* (the object case was pinned, the array case was not),
duplicate-key last-wins, and prop insertion order.

Also corrected: the Maven-vs-AOSP divergence is not just `BigDecimal` — it is
about ten differences including `-0`, `+5`, duplicate keys, and raw control
characters. "Fair except for numbers" was wrong; it is fair for the conservative
inputs the suite uses, and the fuzzer against vendored AOSP is what actually
establishes fidelity.
