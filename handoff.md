# Seen — Handoff

_Last updated: 2026-07-03. Read this before making changes._

## Status: v0.1.0 — feature-complete, integrated, UX redesign done, verified live

### 2026-07-03 UX/UI pass (Paper theme)
The menu bar and Settings were rebuilt for humans (agents use the API/MCP/CLI,
never these surfaces), borrowing Heard's "Paper" design language. Verified
running with Screen Recording granted, in light **and** dark.

- **`SeenApp/DesignSystem.swift`** (new) — Paper palette via `Color(light:dark:)`,
  cards, pills, `StatusDot`, key chips, Paper button styles, `SeenMark` (eye
  glyph), and `Hotkey` formatting (Carbon-flag ↔ human glyphs).
- **Menu bar → `.menuBarExtraStyle(.window)`** custom panel (`MenuContent.swift`):
  status header (Ready / capture flash / active-session), themed capture rows
  with the hotkey shown as ⌃⌥⌘S, an **Agent bridge** status line + one-click
  "copy `claude mcp add`". Live-updates confirmed against real capture events.
- **Hotkey representation bug fixed**: the recorder stored NSEvent modifier
  flags into a field `RegisterEventHotKey` reads as **Carbon** flags, so
  recorded shortcuts silently misfired. Recorder now converts to Carbon on
  capture; display is key-chip glyphs; default corrected to ⌃⌥⌘S (Carbon 6400).
- **Settings → sidebar shell** (`SettingsView.swift`): General / Hotkey /
  Destination / **Agent Access** / Permissions. The old weak "API Status" tab
  is now **Agent Access** — live bridge-status hero + copy-paste connect
  commands, socket/curl demoted to a Details card.
- **`AppState.serverStatus`** now reflects the real `server.start()` result
  (running/starting/failed), surfaced in the panel and Agent Access hero.
  Closes the fire-and-forget rough edge below.
- Onboarding reskinned to Paper (`OnboardingView.swift`).

### 2026-07-08 permission hardening (Seen only ever asks for Screen Recording)
The hotkey used to make Seen prompt for network / Documents / Automation /
Photos. Root cause: the default push spawned `claude` as a child of Seen, and
TCC attributes a child's prompts to the parent; plus the default save dir was
`~/Pictures`. Three fixes:
- **Default save dir → `~/Library/Application Support/Seen/Captures`**
  (`SeenPaths.defaultSaveDirectory`) — off `~/Pictures`, no TCC "Pictures" prompt.
- **Command-template pushes disclaim TCC responsibility** — `DefaultProcessRunner`
  now `posix_spawn`s with `responsibility_spawnattrs_setdisclaim` (dlsym'd,
  graceful fallback) so a spawned agent owns its own prompts. Verified the SPI
  resolves on macOS 15.
- **Default destination → Clipboard** (`AppSettings`) — spawns nothing.
- Migration for existing installs: the persisted `pushDestination` /
  `saveDirectoryPath` keys may hold the old values; clearing them (or picking
  Clipboard / a new folder in Settings) adopts the new defaults.

Verified live: settings-opens-in-front fix, Destination pane + new Include
control, record→fire hotkey (⌃⌥⌘S records → displays → fires a real capture),
captures landing in the new dir, `/config` reporting the new path. **Not**
pixel-verified: the session-active panel header ("Capturing on a schedule") —
the `.window` panel dismisses on focus loss so it couldn't be screenshotted;
it's driven by the same `AppState` observer path that the capture-flash state
(which *was* verified live) uses, so it's logically sound but unconfirmed visually.

---

## Original status: feature-complete, integrated, awaiting first real-world run

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
- **Loopback TCP escape hatch** (Settings → Agent Access) is specced in
  ARCHITECTURE.md §3 but not implemented — UDS only for now.
- **App icon** is SF Symbols only; no .icns asset (menu bar uses `eye`
  variants; `SeenMark` is a drawn eye glyph used in Settings/onboarding).
- **Launch at login** not implemented (SMAppService would be the way).
- **WebP encoding** is the ideal default for the agent path (lossless-quality
  text, smaller than PNG, accepted by Claude vision) but macOS ImageIO ships no
  WebP *encoder* — `CGImageDestinationCopyTypeIdentifiers()` omits
  `org.webmproject.webp` (verified 2026-07-08). Default is PNG instead; the
  `webp` case is kept in `ImageFormat` and the encoder throws a clean
  `unsupportedFormat`. Future enhancement: add a `libwebp` /
  `SDWebImageWebPCoder` encoder path, then switch the default to WebP.
- **HEIC** was removed from `ImageFormat` (2026-07-08): best compression, but
  Claude's vision API does not accept `image/heic` (only jpeg/png/gif/webp), so
  a HEIC capture handed to an agent 400s. Re-add the case when the Claude API
  starts accepting HEIC. (AVIF is encodable on macOS but blocked for the same
  reason — no Claude support.)
- ~~Composition starts the socket server fire-and-forget; failure only NSLogs.~~
  Fixed 2026-07-03: `server.start()` result drives `AppState.serverStatus`,
  shown in the panel + Agent Access hero (NSLog kept for the failure detail).

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
