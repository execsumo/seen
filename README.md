# Seen

A macOS menu bar app that acts as a **vision bridge for CLI-based LLM agents**:
agents pull screenshots and OCR text from your screen on demand through a local
API, and you push screen context into your agent session with a global hotkey.

- **Capture** all displays, one display, an app's windows, or a single window —
  via ScreenCaptureKit one-shots (no persistent streams, near-zero idle cost).
- **OCR** with Apple's Vision framework (`.accurate`, on-device), run on the
  full-resolution capture *before* downscaling so small text survives.
- **Token-aware images**: downscaled to 1568 px longest edge and encoded PNG
  automatically — lossless, so on-screen text stays sharp for the vision model at
  no extra token cost (Claude bills images by dimensions, not bytes). No knobs to
  get wrong. Agents can override format (e.g. JPEG for a smaller payload), quality,
  and size per request.
- **Three access doors** for agents: an MCP stdio server, a `seen` CLI, and a
  raw HTTP-over-Unix-socket API.
- **Interval capture** with compiled-in safety caps no agent can override.
- **Global hotkey** that captures your screen and copies the path (and OCR text)
  to the clipboard, ready to paste into any agent session.

Requires macOS 15+, Apple Silicon recommended. No Xcode needed — Command Line
Tools are enough.

## Installation

**Via Homebrew (Recommended)**

```bash
brew tap execsumo/tap
brew install --cask seen
```

To update to the latest version:
```bash
brew upgrade --cask seen
```

### Manual Build

```bash
swift build                 # compile everything
swift run SeenTests         # run the test suite (executable runner, no XCTest)
./scripts/bundle.sh         # build → Seen.app → /Applications (auto-signs:
                            #   Developer ID → "Dev Cert" → ad-hoc fallback)
./scripts/bundle.sh --release --sign "Dev Cert"   # options
```

Launch **Seen** from /Applications. First run walks you through granting
**Screen Recording** (the only permission Seen needs). Stable code signing
keeps that grant across rebuilds.

## Programmatic access

The app serves HTTP over a Unix domain socket at
`~/Library/Application Support/Seen/seen.sock` (mode 0600 — only your user's
processes can connect; nothing listens on the network). Full endpoint
reference: [docs/api.md](docs/api.md).

### 1. MCP (recommended for agents)

```bash
claude mcp add seen -- seen mcp          # Claude Code
# codex/cline/agy: register `seen mcp` as a stdio MCP server in their config
```

Tools exposed: `capture_screen(target?, output?, max_dimension?)` (returns the
image inline as MCP image blocks + OCR text + saved path), `list_targets`,
`start_watch`, `stop_watch`, `watch_status`. Targets are strings: `"all"`,
`"display:<id>"`, `"app:<name>"`, `"window:<id>"`.

### 2. `seen` CLI

```bash
seen health                              # daemon + permission status
seen targets                             # list displays and capturable apps
seen capture --app "Google Chrome" --ocr-only
seen capture --json                      # all displays, image+text, JSON out
seen watch start --interval 10s --duration 5m
seen watch list / seen watch stop <id>
seen open                                # open the screenshots folder
```

Install the CLI somewhere on your PATH: `cp .build/debug/seen /usr/local/bin/`.

### 3. Raw HTTP

```bash
curl --unix-socket ~/Library/Application\ Support/Seen/seen.sock \
     http://seen/health
curl --unix-socket ~/Library/Application\ Support/Seen/seen.sock \
     -d '{"target":{"app":"Teams"},"output":"both"}' http://seen/capture
```

### Safety caps (compiled in, not configurable)

Interval sessions: interval ≥ 5 s, duration ≤ 30 min, ≤ 2 concurrent sessions,
≤ 200 captures per session. Out-of-bounds requests are rejected with an
explicit error, never silently clamped.

## Hotkey push

Set a global hotkey in **Settings → Hotkey** (default ⌃⌥⌘S). On press, Seen
captures your screen and copies the capture's file path — and its OCR text — to
the clipboard, so you can paste it into any agent session. In **Settings →
Destination** you choose what the push *includes* (image + text, image only, or
text only; agents still pick their own output per request).

Delivery is clipboard-only by design: copying spawns nothing under Seen, so a
capture never drags a child process's permission prompts onto the app. Agents
that want a capture delivered elsewhere use the API/MCP/CLI directly.

## Storage & menu bar

Every capture — API, MCP, CLI, hotkey, or menu — is saved to the directory set
in **Settings → General** (default `~/Library/Application Support/Seen/Captures`)
as `capture_2026-07-03_13-50-22_display-1.png`. The default is deliberately kept
out of `~/Pictures` so writing captures never triggers a TCC "Pictures folder"
prompt — point it at `~/Pictures/Seen` in Settings if you prefer. The menu bar
icon shows three states: idle, recent capture (3 s flash), and interval-session
active. The menu is a Paper-styled panel: a status header (which doubles as the
agent-bridge indicator — "Agent Bridge Running" when the socket is live), Capture
Now, per-app capture, the screenshots folder, and running-session stops. Agents
connect via the README's setup commands, not the menu.

## Architecture

Clean Architecture in one SPM package — see [ARCHITECTURE.md](ARCHITECTURE.md)
for the full design and [docs/api.md](docs/api.md) for the API contract.

```
SeenKit/Domain      frozen contract: models, protocols, session caps, errors
SeenKit/Capture     ScreenCaptureKit engine          (implements ScreenCapturing)
SeenKit/OCR         Vision text recognition          (implements TextRecognizing)
SeenKit/Imaging     resize + encode via ImageIO      (implements ImageEncoding)
SeenKit/Storage     timestamped file persistence     (implements CaptureStoring)
SeenKit/Coordinator capture→OCR→encode→store orchestration + event fan-out
SeenKit/Sessions    interval sessions, hard caps enforced
SeenKit/Server      HTTP codec, UDS server, router, API client, MCP handler
SeenKit/Push        hotkey delivery: templates, tmux, clipboard
SeenKit/AppCore     pure app logic: settings, icon state (headless-testable)
SeenApp             SwiftUI menu bar shell + Settings + composition root
seen-cli            `seen` CLI + `seen mcp` stdio shim
SeenTests           executable test runner (works with CLT alone)
```

Everything downstream of Domain depends on protocols only; `swift run
SeenTests` exercises the whole stack with mocks (38 tests) — no Screen
Recording permission needed to develop.

## Development

- `Heard`-style workflow: no Xcode project; edit, `swift build`, bundle.
- Tests: add a `[TestCase]` array in `Sources/SeenTests/`, register it in
  `AllTests.swift`.
- The API contract in `docs/api.md` is normative — server, CLI, and MCP shim
  all conform to it; change the doc first.
