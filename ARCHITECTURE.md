# Seen — Architecture

> Status: **PROPOSED** — awaiting approval before implementation.

Seen is a macOS menu bar app that acts as a "vision bridge" for CLI-based LLM
agents: agents pull screenshots/OCR on demand through a local API, and the user
pushes screen context into their LLM session with a global hotkey.

Target: macOS 15.0+, Apple Silicon, Swift 6 / SwiftUI, Swift Package Manager
(no Xcode project — same setup as Heard).

---

## 1. Package layout

```
seen/
├── Package.swift
├── Sources/
│   ├── SeenKit/            # All logic lives here (library, fully testable)
│   │   ├── Domain/         # Models + protocols, zero framework imports
│   │   ├── Capture/        # ScreenCaptureKit engine
│   │   ├── OCR/            # Vision framework text recognition
│   │   ├── Imaging/        # Resize + encode pipeline
│   │   ├── Storage/        # Timestamped file persistence
│   │   ├── Sessions/       # Interval-capture session manager (hard caps)
│   │   ├── Server/         # HTTP-over-Unix-socket API router
│   │   └── Push/           # Hotkey → destination-CLI pipeline
│   ├── SeenApp/            # Menu bar app (MenuBarExtra, Settings, hotkey reg)
│   └── seen-cli/           # `seen` — thin client for the socket API
│                           #   (`seen mcp` subcommand = stdio MCP shim)
├── Tests/SeenKitTests/
├── scripts/bundle.sh       # build → .app bundle → /Applications (Heard-style)
└── README.md
```

**Dependency rule (Clean Architecture):** `Domain` imports nothing.
`Capture/OCR/Imaging/Storage` implement Domain protocols (`ScreenCapturing`,
`TextRecognizing`, `ImageEncoding`, `CaptureStoring`) and are injected into the
application-layer `CaptureCoordinator`. `SeenApp` and `Server` are thin
adapters over the coordinator. Every service is mockable; SeenKit compiles and
tests headlessly.

## 2. Core components

### CaptureCoordinator (application layer)
Single entry point for every capture, regardless of origin (API, hotkey, menu).
Takes a `CaptureRequest`, orchestrates capture → OCR → encode → store, returns
a `CaptureResult`. Emits events the menu bar icon and server both observe.

```swift
struct CaptureRequest {
    enum Target { case allDisplays; case display(Int); case app(String); case window(WindowID) }
    enum Output { case image, text, both }
    var target: Target = .allDisplays      // default: every connected screen
    var output: Output = .both
    var maxDimension: Int? = nil           // override settings default
}
```

### Capture engine — ScreenCaptureKit
- `SCShareableContent` for display/window enumeration; `SCScreenshotManager`
  for one-shot captures (no persistent stream — zero idle cost).
- **All displays** (default): one image per display, returned as a set.
- **App by name**: fuzzy match against running apps' windows
  (`SCRunningApplication` / `SCWindow`); captures all of that app's on-screen
  windows, bypassing the multi-monitor default.
- Exposes `GET /displays` and `GET /apps` so agents can discover valid targets
  instead of guessing names.

### OCR — Vision framework
- `VNRecognizeTextRequest`, `.accurate` mode, language correction on — runs on
  the Neural Engine on Apple Silicon; typical full-screen pass is <300 ms.
- OCR runs on the **full-resolution** capture *before* downscaling, so small
  text stays readable even when the stored image is resized.
- Returns plain text (reading order) and reports "no text found" explicitly.

### Imaging pipeline (token-cost control)
- Downscale longest edge to **1568 px** by default (Anthropic's vision
  sweet spot — larger images are resized server-side anyway, so bigger only
  costs tokens). Configurable per-request and in Settings.
- Encode via ImageIO: **JPEG quality 0.75 default**; HEIC and WebP offered
  where the OS supports encoding them. Typical Retina full-screen lands around
  150–400 KB.

### Interval sessions (with non-bypassable caps)
- `POST /sessions {interval, duration, target, output}` → session id;
  `DELETE /sessions/:id` stops early.
- Hard limits compiled into `SessionLimits` in Domain — **not** configurable
  via API or Settings: min interval **5 s**, max duration **30 min**, max **2**
  concurrent sessions, max **200** captures per session. Requests beyond the
  caps are clamped-or-rejected with an explicit error, never silently obeyed.
- Sessions survive nothing: app quit = sessions die (intentional).

## 3. Programmatic access — one engine, three doors

The menubar app owns the capture capability (TCC grant, hotkey, sessions) and
serves **HTTP over a Unix domain socket**
(`~/Library/Application Support/Seen/seen.sock`) as the substrate. Two thin
clients ride on it; agents pick whichever door fits:

1. **`seen mcp` (primary for agents)** — a stdio MCP server that proxies to
   the socket. Registered once per agent
   (`claude mcp add seen -- seen mcp`; equivalents for codex/cline/agy).
   - Tools are typed and self-describing — agents discover
     `capture_screen(target, output)` with schema at connect time.
   - Tool results return the screenshot **inline as MCP image content
     blocks** (plus the saved file path), so the capture lands in the agent's
     vision context in one round trip — no path-then-read-file second step.
   - Tool set: `capture_screen`, `list_targets`,
     `start_watch` / `stop_watch` / `watch_status` (session caps enforced
     server-side, same as every door).
   - Why a shim and not MCP as the transport: stdio MCP servers are spawned
     per client session; a short-lived child process can't own the Screen
     Recording grant, menu bar, or running sessions. The long-lived app must
     hold the capability; MCP proxies to it.
2. **`seen` CLI** — ergonomic front door for humans and shell scripts.
3. **Raw HTTP over the socket** — `curl --unix-socket ~/.../seen.sock
   http://seen/capture` for anything that speaks neither MCP nor wants the CLI.

Why UDS (not a localhost TCP port) as the substrate:
- **Security is filesystem-native.** Socket file is `0600` — only the logged-in
  user's processes can connect. No auth tokens to mint/store/leak, nothing
  listening on the network, invisible to other users and to the LAN.
- Optional escape hatch in Settings: enable loopback TCP (127.0.0.1, random
  port, bearer token auto-generated) for tools that can't speak UDS. Off by
  default. MCP-over-streamable-HTTP can be layered here later if ever needed.

Considered and rejected:
- **WebSockets** — value is server-push over a held-open connection; CLI
  agents are request/response loops that don't hold connections between
  turns. Interval-session results are better served by files-on-disk +
  `watch_status`, and MCP has progress notifications if push is ever wanted.
- **XPC** — native and fast, but invisible to CLI agents and curl.
- **Apple Events / AppleScript** — legacy, poor structured data.
- **Daemonless direct-capture CLI** — TCC attribution for CLI tools goes to
  the invoking terminal/host app, so permissions become per-context and
  messy; the daemon must exist anyway for hotkey/menubar/sessions.

The server itself is a minimal implementation on `Network.framework`
(`NWListener` supports UDS) — no heavyweight web-framework dependency.

### API surface (v1)

| Endpoint | Purpose |
|---|---|
| `GET /health` | liveness + version + permission status |
| `GET /displays` | connected displays (id, resolution) |
| `GET /apps` | capturable apps/windows |
| `POST /capture` | one-shot capture; body = CaptureRequest; returns JSON with file path(s), OCR text, dimensions, byte size |
| `POST /sessions` | start interval capture (capped) |
| `GET /sessions` / `DELETE /sessions/:id` | inspect / stop |

`POST /capture` returns file **paths** (captures are always saved to the
configured directory) plus OCR text inline; agents with vision read the file,
text-only flows use the OCR field. Naming: `capture_2026-07-03_13-50-22_display1.jpg`.

### `seen` CLI examples

```bash
seen capture                          # all displays, image+text
seen capture --app "Google Chrome" --ocr-only
seen watch --interval 10s --duration 5m
seen open                             # open screenshots folder
```

## 4. Hotkey push pipeline

- Global hotkey via Carbon `RegisterEventHotKey` (sandboxless SPM app; no
  third-party dependency), recorder UI in Settings.
- On press: capture per the configured default → then hand off to the
  configured **destination**, one of:
  1. **Command template** (recommended default) — run a user-defined shell
     template with `{path}` / `{text}` placeholders, e.g.
     `claude -p "look at {path}"`. Presets shipped for claude / codex / cline.
  2. **tmux pane** — `tmux send-keys` the path into a chosen pane, which drops
     the capture into an *ongoing* CLI session (this is the "insert into
     existing session" mechanism; herdr panes are tmux panes).
  3. **Clipboard** — path + text copied; user pastes anywhere.
- If the destination session isn't running, the command template path starts a
  new one (behavior 1 = new session, behavior 2 = existing session).

## 5. Menu bar UI & state

- `MenuBarExtra` with template icon in three states: **idle** (eye), **recent
  capture** (eye + flash, ~3 s), **interval session active** (eye + recording
  dot, persists while any session runs).
- Menu: Capture Now, Capture App ▸, Open Screenshots Folder, active-session
  list with Stop buttons, API status line (socket path, copyable curl example),
  Settings, Quit.
- Settings panes: General (save directory, image format/quality/max dimension),
  Hotkey, Destination (LLM CLI integration), API (UDS info, optional TCP
  toggle), Permissions (live status + "Open System Settings" deep links).

## 6. Permissions handling

- **Screen Recording** — required. On first launch a guided sheet explains the
  prompt, triggers it, and deep-links to
  `System Settings → Privacy & Security → Screen Recording`; the API returns a
  structured `permission_required` error (not a silent black image) until
  granted. `GET /health` reports permission state so agents can self-diagnose.
- **Accessibility** — *not required* for any core feature (tmux/command
  destinations avoid keystroke injection). Only requested if the user opts
  into a future "type into frontmost app" destination.
- Stable code-signing via `bundle.sh --sign` (Heard pattern) so TCC grants
  survive rebuilds.

## 7. Quality & testing

- Swift 6 strict concurrency; services are `actor`s where they own mutable
  state (session manager, server).
- Unit tests: coordinator orchestration (mocked services), session-cap
  enforcement, request parsing/routing, filename formatting, image-pipeline
  dimensions. Integration smoke test: boot server on a temp socket, curl it.
- Low idle footprint: no capture streams held open, server on demand-driven
  NWListener, no timers when no session is active.

## 8. Implementation plan (delegated via herdr)

Work is split into three parallel workstreams for delegate CLIs, each in an
isolated worktree with a written spec + Definition of Done; I integrate,
review, and own the final merge:

| Workstream | Scope | Delegate |
|---|---|---|
| A — Core engine | Domain, Capture, OCR, Imaging, Storage + tests | codex |
| B — API surface | Server (UDS/NWListener), Sessions, `seen` CLI + `seen mcp` shim + tests | cline |
| C — App shell | SeenApp UI, Settings, hotkey, Push pipeline, bundle.sh | agy (antigravity) |

Order: scaffold (Package.swift + Domain protocols) lands first from me so all
three delegates build against the same interfaces; A/B/C then run in parallel;
integration + README + end-to-end verification last.
