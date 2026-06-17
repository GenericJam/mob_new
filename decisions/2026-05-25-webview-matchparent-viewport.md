# Android WebView fills its bounds (MATCH_PARENT)

- Date: 2026-05-25
- Status: accepted

## Context
The generated `MobWebView` composable created its `WebView` with no explicit
layout params, so Android defaulted it to `wrap_content`. Any web app using
full-viewport CSS (`100vh` / `100%`) — e.g. an embedded xterm.js terminal —
measured its container as 0px and rendered blank, even though the page loaded,
JavaScript ran, and the WebSocket connected. Surfaced while building a
terminal-in-mob proof-of-concept.

## Decision
Set the WebView's `layoutParams` to `MATCH_PARENT × MATCH_PARENT` and enable
`useWideViewPort` + `loadWithOverviewMode`, so the page's viewport meta is
honoured and `vh` units resolve to the view's real height.

## Consequences
Full-viewport pages render correctly. iOS WKWebView is unaffected (sized by
its SwiftUI frame). Shipped in mob_new 0.3.11 with a generator test asserting
the rendered `MobBridge.kt` carries these settings.
