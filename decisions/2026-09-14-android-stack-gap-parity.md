# Android stack gap parity
- Date: 2026-09-14
- Status: accepted

## Context

Mob documents `gap` as the space between Row or Column children and resolves
spacing tokens before serializing a tree. The generated Android bridge ignored
that prop for both stacks even though the iOS renderer and the separate Wrap
primitive consume their spacing props.

## Decision

Generated Columns pass `gap` to `Arrangement.spacedBy` as their vertical
arrangement. Generated Rows pass the same value as their horizontal
arrangement. An absent value becomes zero, preserving existing output.

## Consequences

- Row and Column spacing now follow the same authored prop on Android and iOS.
- The arrangement stays on the stack's main axis. Cross-axis alignment and
  relative child-weight distribution are unchanged, while gaps reduce the
  absolute main-axis space available to weighted children.
- Existing generated apps must regenerate or copy the bridge change before
  they benefit.

## Verification

- A generated-project regression test pins both stack branches and the
  `gap`-to-`Arrangement.spacedBy` mapping.
- The full `mob_new` suite and generated Android Kotlin lint pass against the
  matching MOB-234 `mob` worktree.
- The same bridge change compiled, installed, and pushed a Crosscourt OTP
  release on a physical Moto G Power (2021), serial `ZY22DP6HFL`. After the
  phone was unlocked, the drawer opened successfully: its 9dp wordmark Row gap
  rendered visibly, the adjacent labels remained on one line, the process
  stayed alive, and recent logs contained no fatal exception or OOM.
