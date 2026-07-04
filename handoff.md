# Seen — Handoff

_Last updated: 2026-07-03. Read this before making changes._

## Status: v0.1.0 — feature-complete, integrated, awaiting first real-world run

All three workstreams are merged to `main`, the full suite passes
(`swift run SeenTests` — 38/38), and `./scripts/bundle.sh` installs
`/Applications/Seen.app` signed with the Developer ID identity (stable TCC).

What has **not** happened yet: real-world verification with Screen Recording
granted. Everything below "Verified" is tested only through mocks/headless
paths.

## Verified (by tests or direct execution)

- Build clean (zero warnings), 38/38 tests: 11 domain + 15 core engine +
  4 shell + 8 API suites.
- UDS server end-to-end over a real socket (temp path): /health, /capture,
  0600 socket mode, stale-socket replacement.
- MCP handler: initialize handshake, tools/list, capture_screen returning
  image + text blocks (against a mock API client).
- Session caps: rejection semantics, concurrent limit, 3-consecutive-failure
  abort, instant-sleep loop behavior.
- Encoder math (downscale/aspect/no-upscale), OCR on CoreText-rendered
  images, filename convention + collision suffixes.
- `seen --help` and subcommand tree.

## Not yet verified (needs the app running with permission granted)

1. Real ScreenCaptureKit captures (all-displays, app-target, window-target).
2. The permission onboarding flow and deep links.
3. Hotkey → push pipeline end-to-end (command template / tmux / clipboard).
4. Menu bar icon state transitions driven by real events.
5. MCP registered in a real agent (`claude mcp add seen -- seen mcp`) —
   inline image blocks rendering in an actual session.
6. WebP encoding on this OS version (test asserts encode-or-clean-error).

## Known rough edges / next work

- **CLI human output** prints Swift struct dumps for `health`/`targets`/`watch
  list` instead of formatted text (see `SeenCommand.swift`) — functional, ugly.
- **Loopback TCP escape hatch** (Settings → API) is specced in
  ARCHITECTURE.md §3 but not implemented — UDS only for now.
- **App icon** is SF Symbols only; no .icns asset.
- **Launch at login** not implemented (SMAppService would be the way).
- Composition starts the socket server with `Task {}` fire-and-forget; server
  start failure only logs via NSLog. Consider surfacing in the menu.

## Architecture in 30 seconds

`SeenKit/Domain` is the frozen contract (models, protocols, `SessionLimits`,
errors, file naming). Everything implements or consumes those protocols:
Capture (ScreenCaptureKit) / OCR (Vision) / Imaging (ImageIO) / Storage →
orchestrated by the `CaptureCoordinator` actor (single entry point, event
fan-out). `Server/` speaks HTTP/1.1 over a 0600 UDS via NWListener and also
hosts `MCPHandler`; `Sessions/` enforces the compiled-in caps;
`Push/` delivers to command templates / tmux / clipboard; `AppCore/` holds
pure app logic so the executable-target test runner can reach it.
`SeenApp/Composition.swift` is the only place concrete types meet.
Full design: ARCHITECTURE.md. API contract (normative): docs/api.md.

## Conventions

- No Xcode; CLT-only. Tests = executable runner: add a `[TestCase]` array,
  register one line in `Sources/SeenTests/AllTests.swift`.
- `docs/api.md` is normative for server/CLI/MCP — change the doc first.
- Rebuild+install with `./scripts/bundle.sh` (keeps signing identity stable so
  the Screen Recording grant survives).
- Domain changes are a big deal — everything downstream builds against it.

## History notes

Built 2026-07-03 by three parallel delegate agents (herdr) against frozen
Domain protocols + spec contracts in `specs/` (kept for reference): A = capture
engine (cline), B = API surface (agy, after a first cline instance stalled),
C = app shell (agy). Integration (placeholder swap in Composition, session
event wiring, mock rename) by the orchestrator. The delegate worktrees under
`../seen-worktrees/` are historical; `main` is the source of truth.
