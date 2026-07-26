# Seen HTTP API v1

Served by the menu bar app over a Unix domain socket. This document is the
contract: the server (Server/), the CLI, and the MCP shim all conform to it.

- **Socket:** `~/Library/Application Support/Seen/seen.sock` (mode `0600`).
  Override with `SEEN_SOCKET` env var (tests use this). Resolve via
  `SeenPaths.socketPath`.
- **Protocol:** HTTP/1.1, JSON bodies. The authority/host in URLs is ignored.
- **Dates:** ISO 8601 (`JSONEncoder.dateEncodingStrategy = .iso8601`).
- **Example:** `curl --unix-socket ~/Library/Application\ Support/Seen/seen.sock http://seen/health`

## Errors

Any non-2xx response has body `{"error": {"code": "...", "message": "..."}}`.
`code` is `SeenError.code`; mapping to status:

| code | status |
|---|---|
| `bad_request`, `unsupported_format`, `session_limit_exceeded` | 400 |
| `permission_required` | 403 |
| `target_not_found`, `session_not_found` | 404 |
| `capture_failed`, `encoding_failed`, `storage_failed` (+ any unexpected error → `internal`) | 500 |

## Endpoints

### `GET /health`
```json
{"status": "ok", "version": "0.1.0", "screenRecordingPermission": true, "activeSessions": 0}
```
Always 200 when the daemon is up, even without permission — agents use the
`screenRecordingPermission` field to self-diagnose.

### `GET /config`
```json
{"saveDirectoryPath": "/Users/x/Library/Application Support/Seen/Captures", "defaultFormat": "png", "defaultQuality": 0.75, "defaultMaxDimension": 1568}
```

### `GET /displays`
```json
{"displays": [{"id": 1, "width": 3456, "height": 2234, "name": "Built-in Display"}]}
```

### `GET /apps`
```json
{"apps": [{"id": 4242, "appName": "Google Chrome", "bundleID": "com.google.Chrome", "title": "Inbox"}]}
```

### `POST /capture`
Body: a `CaptureRequest` (every field optional):
```json
{
  "target": "all",              // or {"display": 1} | {"app": "Chrome"} | {"window": 4242}
  "output": "both",             // "image" | "text" | "both"
  "format": "png",              // "png" (default) | "jpeg" | "webp"; webp not encodable on macOS ImageIO yet
  "quality": 0.75,              // lossy formats only (jpeg); PNG ignores it
  "maxDimension": 1568
}
```
200 → a `CaptureResult`:
```json
{
  "items": [{
    "path": "/Users/x/Library/Application Support/Seen/Captures/capture_2026-07-03_13-50-22_display-1.png",
    "sourceLabel": "display-1",
    "width": 1568, "height": 1013, "byteSize": 214321,
    "text": "OCR text…"        // absent = OCR not requested; "" = ran, none found
  }],
  "timestamp": "2026-07-03T13:50:22Z"
}
```
The image file is **always saved**, even for `"output": "text"`.

### `POST /sessions`
Body: `{"interval": 10, "duration": 300, "capture": { …CaptureRequest… }}`
201 → a `SessionInfo`:
```json
{"id": "UUID", "request": {…}, "startedAt": "…", "endsAt": "…", "captureCount": 0}
```
400 `session_limit_exceeded` if it violates `SessionLimits` (min interval 5 s,
max duration 30 min, ≤2 concurrent, ≤200 captures/session — compiled-in caps).

### `GET /sessions`
```json
{"sessions": [ …SessionInfo… ]}
```

### `DELETE /sessions/{uuid}`
204 on success; 404 `session_not_found` otherwise.

## MCP tools (`seen mcp`)

stdio JSON-RPC shim proxying to this API; one JSON-RPC message per line.

### Protocol version negotiation

`initialize` echoes the client's requested `protocolVersion` when it is one the
shim supports — `2024-11-05`, `2025-03-26`, `2025-06-18` — as the MCP spec
requires. If the request asks for an unsupported version, or omits
`protocolVersion` entirely, the shim replies with its latest (`2025-06-18`) and
the client decides whether to proceed.

The supported list is broad because the shim's behavior does not vary by
version: the tool set and result shapes are identical across all three. Adding
a version that *does* change behavior means branching here, not just widening
the list.

Tools:

| tool | maps to | notes |
|---|---|---|
| `capture_screen(target?, output?, format?, max_dimension?)` | `POST /capture` | `format` is `"png"` (default) or `"jpeg"`. Result content: one `image` block per item (base64 + mimeType) when output includes image, one `text` block with OCR text + saved paths |
| `list_targets()` | `GET /displays` + `GET /apps` | single `text` block of JSON |
| `start_watch(interval_seconds, duration_seconds, target?)` | `POST /sessions` | |
| `stop_watch(session_id)` | `DELETE /sessions/{id}` | |
| `watch_status()` | `GET /sessions` | |

`target` in tool inputs: `"all"` (default), `"display:<id>"`, `"app:<name>"`,
or `"window:<id>"` — flattened to strings because MCP tool schemas favor
simple parameters; the shim translates to the JSON target shape.

## CLI Commands (`seen`)

In addition to the server endpoints, the `seen` binary provides local setup commands:

Setup is organised by *harness*, not by artifact: one subcommand per agent, each
installing everything that harness supports.

- `seen setup claude [--project] [--mcp-only] [--skill-only] [--yes]`: Registers the MCP server via `claude mcp add` (scope `user`, or `project` with `--project`) and installs `SKILL.md` to `~/.claude/skills/seen/` (or `./.claude/skills/seen/`).
- `seen setup codex [--mcp-only] [--skill-only] [--yes]`: Registers the MCP server via `codex mcp add` and installs `SKILL.md` to `~/.codex/skills/seen/`. Global only — `--project` is rejected, since Codex stores both globally.
- `seen setup cursor [--project] [--mcp-only] [--config <path>]`: Merges the `seen mcp` server into `~/.cursor/mcp.json` (or `./.cursor/mcp.json`). Cursor has no skills directory, so it declares neither `--skill-only` nor `--yes`, and the skill step reports as skipped.
- `seen setup antigravity [--project] [--mcp-only] [--skill-only] [--yes] [--config <path>]`: Merges into `~/.gemini/config/mcp_config.json` (or `./.agents/mcp_config.json`) and installs `SKILL.md` to `~/.gemini/config/skills/seen/` (or `./.agents/skills/seen/`). Antigravity's config schema is identical to Cursor's, so both share one merge implementation.

`--config <path>` overrides the destination for the file-based harnesses; the
CLI-based ones (Claude Code, Codex) own their own config location.

Every command reports each step independently and exits 0 when each is either
applied or already current; a non-zero exit means a step genuinely failed. A
skill file that exists and differs prompts before being overwritten unless
`--yes` is passed.

