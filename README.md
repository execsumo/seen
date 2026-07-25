# Seen

**Let your CLI agent see your screen.**

Seen is a macOS menu bar app that gives coding agents — Claude Code, Cursor,
Codex, anything that speaks MCP — screenshots and on-screen text on demand. Ask
"what's on my screen?" and the agent just looks.

Requires macOS 15+.

---

## Quickstart

**1. Install**

```bash
brew install --cask execsumo/tap/seen
```

That's the whole install. It puts `Seen.app` in `/Applications` and the `seen`
command on your PATH.

**2. Launch it and grant one permission**

Open **Seen** from your Applications folder. It walks you through granting
**Screen Recording** — the only permission it ever asks for. macOS may ask you
to quit and reopen Seen for the grant to take effect.

Seen then lives in your menu bar. There's no window to keep open.

**3. Check it works**

```bash
seen health
```

**4. Connect your agent**

```bash
claude mcp add seen -- seen mcp
```

Now ask Claude Code *"what's on my screen right now?"* — that's it.

<details>
<summary><b>Cursor, Codex, and other agents</b></summary>

Cursor has no `mcp add` command, so add it to `~/.cursor/mcp.json` (all
projects) or `.cursor/mcp.json` (one project):

```json
{
  "mcpServers": {
    "seen": { "command": "seen", "args": ["mcp"] }
  }
}
```

Any other MCP-capable agent: register `seen mcp` as a **stdio** server. The
command is `seen`, the argument is `mcp`.
</details>

<details>
<summary><b>Give Claude Code deeper instructions (optional)</b></summary>

The repo ships an agent skill that teaches Claude Code when to look at your
screen and how to choose between OCR text and images:

```bash
mkdir -p ~/.claude/skills/seen
curl -o ~/.claude/skills/seen/SKILL.md \
  https://raw.githubusercontent.com/execsumo/seen/main/.claude/skills/seen/SKILL.md
```
</details>

**Updating:** `brew upgrade --cask seen`

---

## Using it

### From your agent

Once MCP is connected, just ask. Behind the scenes the agent gets
`capture_screen`, `list_targets`, `start_watch`, `stop_watch`, and
`watch_status`.

### From your terminal

```bash
seen capture                             # capture everything
seen capture --app "Google Chrome"       # just one app's windows
seen capture --ocr-only                  # text only, no image
seen targets                             # what can I capture?
seen watch start --interval 10s --duration 5m   # capture on a schedule
seen open                                # open the screenshots folder
```

Add `--json` to any capture for machine-readable output.

### With a hotkey

Press **⌃⌥⌘S** anywhere to capture your screen and copy the file path and OCR
text to your clipboard, ready to paste into any agent session. Change the
shortcut in **Settings → Hotkey**, and choose what gets copied in
**Settings → Destination**.

Delivery is clipboard-only on purpose: copying launches nothing, so a capture
never drags another program's permission prompts onto Seen.

### Where captures go

`~/Library/Application Support/Seen/Captures/`, named like
`capture_2026-07-03_13-50-22_display-1.png`. Change it in **Settings → General**.

The default deliberately avoids `~/Pictures` so Seen never triggers a "wants to
access your Pictures folder" prompt.

---

## How it works

Seen captures with **ScreenCaptureKit** (one-shots, not persistent streams, so
it costs almost nothing while idle) and reads text with Apple's **Vision**
framework on-device. OCR runs on the full-resolution image *before* downscaling,
so small text survives.

Images are automatically sized for vision models: 1568 px on the longest edge,
PNG. PNG is lossless, so on-screen text stays sharp at no extra token cost —
Claude bills images by dimensions, not bytes. Agents can request JPEG per
capture if they want a smaller payload.

### Three ways in

The app serves HTTP over a Unix domain socket at
`~/Library/Application Support/Seen/seen.sock` (mode 0600 — only your user can
connect; **nothing listens on the network**).

| | Needs | Best for |
|---|---|---|
| **MCP** | the `seen` CLI on PATH | agents — images come back inline |
| **`seen` CLI** | the CLI on PATH | you, at a terminal; scripts |
| **Raw HTTP** | nothing but the running app | anything that can `curl` |

MCP runs *through* the CLI — `seen mcp` is a thin stdio shim over the socket —
so the CLI has to be installed for MCP to work. Homebrew handles that for you.

```bash
curl --unix-socket ~/Library/Application\ Support/Seen/seen.sock \
     -d '{"target":{"app":"Teams"},"output":"both"}' http://seen/capture
```

Full endpoint reference: [docs/api.md](docs/api.md).

### Safety caps

Interval sessions are capped in the binary, and no agent can raise them:
interval ≥ 5 s, duration ≤ 30 min, ≤ 2 concurrent sessions, ≤ 200 captures per
session. Out-of-bounds requests are rejected with an explicit error rather than
silently clamped.

---

## Building from source

No Xcode needed — Command Line Tools are enough.

```bash
swift build                 # compile
swift run SeenTests         # 38 tests, no Screen Recording permission needed
./scripts/bundle.sh         # build → Seen.app → /Applications
./scripts/bundle.sh --no-install   # build without touching /Applications
```

`bundle.sh` embeds the CLI at `Seen.app/Contents/Resources/bin/seen`. To put it
on your PATH from a source build:

```bash
ln -s /Applications/Seen.app/Contents/Resources/bin/seen /usr/local/bin/seen
```

> If you already installed via Homebrew, don't also run `bundle.sh` — it writes
> directly to `/Applications` and Homebrew will lose track of what's installed.
> Pick one.

### Architecture

Clean Architecture in one SPM package — see
[ARCHITECTURE.md](ARCHITECTURE.md) for the full design.

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

Everything downstream of Domain depends on protocols only, so the whole stack is
testable with mocks — no Screen Recording permission needed to develop.

The API contract in [docs/api.md](docs/api.md) is normative: server, CLI, and
MCP shim all conform to it. Change the doc first.
