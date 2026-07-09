---
name: seen
description: See the user's screen via the Seen daemon — take screenshots and read on-screen text (OCR) on demand. Use whenever you need to know what's on screen right now - verifying a UI change, reading an error dialog, checking what an app/meeting/terminal shows, watching the screen over an interval, or when the user says "look at my screen", "what do you see", "screenshot", "capture the screen", or names an app to look at.
---

# Seen — screen capture & OCR for agents

Seen is a menu bar daemon (`/Applications/Seen.app`) exposing screen capture +
Vision OCR over a local Unix socket. Every capture is also saved to disk
(default `~/Library/Application Support/Seen/Captures/capture_<date>_<time>_<source>.jpg`,
≤1568 px, ~300 KB; user-configurable in Settings). Query `seen open` or
`/config`'s `saveDirectoryPath` for the live location.

## Quick recipes (CLI — always available as `seen`)

```bash
seen health                        # daemon up? permission granted?
seen targets                       # displays + capturable apps (find exact names)
seen capture --json                # all displays, image + OCR text
seen capture --app "Chrome" --json # one app's windows only (fuzzy name/bundle match)
seen capture --ocr-only            # text only (image still saved)
seen watch start --interval 10s --duration 5m    # timestamped series to disk
seen watch list / seen watch stop <id>
seen open                          # open the screenshots folder
```

**Typical flow:** `seen capture --json` → parse `items[].path` and
`items[].text` → Read the image file if you need to *see* it; use `text` when
OCR suffices (cheaper than vision). `text` absent = OCR not requested;
`""` = OCR ran, no text found.

To watch something evolve (a build, a meeting, a deploy): `seen watch start`,
do other work, then read the new `capture_*` files after `endsAt`.

## Other doors

- **MCP** (if registered: `claude mcp add seen -- seen mcp`): tools
  `capture_screen(target?, output?, max_dimension?)` — returns the image
  inline as MCP image blocks + OCR text — plus `list_targets`, `start_watch`,
  `stop_watch`, `watch_status`. Targets: `"all"` | `"display:<id>"` |
  `"app:<name>"` | `"window:<id>"`.
- **Raw HTTP** over the socket:
  ```bash
  curl -s --unix-socket ~/Library/Application\ Support/Seen/seen.sock \
       -d '{"target":{"app":"Teams"},"output":"both"}' http://seen/capture
  ```
  Endpoints: /health /config /displays /apps /capture /sessions. Contract:
  `docs/api.md` in the seen repo (`~/projects/seen`).

## Limits & errors

- Interval sessions are hard-capped (compiled in): interval ≥ 5 s, duration
  ≤ 30 min, ≤ 2 concurrent, ≤ 200 captures/session. Out-of-bounds → explicit
  `session_limit_exceeded` error; pick a slower interval or shorter duration.
- `permission_required` → tell the user to enable Screen Recording for Seen
  (System Settings → Privacy & Security); don't retry until they confirm.
- Connection refused / no socket → the app isn't running: `open -a Seen`,
  then retry `seen health`.
- `target_not_found` → run `seen targets` and use an exact name from it.

## Judgment

- Prefer `--app <name>` over full-screen when you only need one app — smaller
  images, less noise, and it avoids capturing unrelated sensitive content.
- Prefer `--ocr-only` when text answers the question; read the image only when
  layout/visuals matter.
- Screenshots may contain sensitive content: don't paste OCR dumps or upload
  captures anywhere external without the user asking.
