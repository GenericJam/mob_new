# Security policy

## Reporting a vulnerability

Email **genericjam@gmail.com** with `[mob_new security]` in the subject. Please
don't open a public issue, pull request or discussion for a vulnerability.

Include what you can of:

- the mob_new version (or commit) and the `mix mob.new` command line you used;
- whether the problem is in the generator itself or in the project it generates
  (name the file);
- steps or a proof of concept that reproduce it;
- what it lets the attacker do.

The same address covers the related packages I maintain: `mob`, `mob_dev` and
the `mob_*` plugins published from
[github.com/GenericJam](https://github.com/GenericJam). If a problem spans
several of them, send one report and I'll coordinate the fixes. Bugs in the
over-the-air update implementation itself belong to the `mob_deliver` packages;
report them the same way and name the package.

## What happens next

- I acknowledge reports within 7 days.
- I confirm or rule out the issue, then fix it in a new release on Hex.
- Once the fix is published, I publish a GitHub security advisory that credits
  you, unless you'd rather not be named.
- Please keep the details private until the fix is released, or for 90 days
  after your report, whichever comes first. If a fix needs longer, I'll tell you
  why and we'll agree on a date.

Generated projects are copies of the templates, so a template fix doesn't reach
apps that already exist. For a template vulnerability, the advisory explains how
to fix an existing project by hand.

## Supported versions

mob_new is pre-1.0. Security fixes go into the next release only, and older
versions don't get backports. Install the latest release with
`mix archive.install hex mob_new`.

## Scope

mob_new generates Mob projects. A mistake in a template ends up in every app
generated from it, so the templates under `priv/templates/mob.new/` are in scope
as much as the generator in `lib/`.

**In scope:**

- **The generator:** writing files outside the chosen destination, or code or
  command injection through app, module or bundle names.
- **Insecure generated defaults:**
  - development distribution enabled in release builds;
  - public or predictable distribution cookies;
  - listeners bound more widely than needed;
  - secrets or private keys that aren't git-ignored, or that get overly
    permissive file modes. One example is the update-signing key that
    `--deliver` creates.
- **The native templates** (the Kotlin, C and Objective-C bridges): how they
  handle deep links, notification intents, WebView messages and JSON, and memory
  safety where outside data reaches native code.
- **Generated LiveView/WebView projects:** what the JavaScript-to-native bridge
  lets a page do, and navigation to content the app didn't intend to load.

**Not vulnerabilities on their own:**

- An existing project's `mix.exs` running code under Mix. Mix trusts it by
  design.
- An authenticated development peer running arbitrary code. That access is the
  point of distribution.
- Bugs in Erlang/OTP, Elixir, Android, Xcode or a third-party library. Report
  those upstream.
