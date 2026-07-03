# Workstream B — API Surface (UDS HTTP server, sessions, CLI, MCP shim)

## 1. OBJECTIVE

Implement Seen's programmatic access: the HTTP-over-Unix-socket server and
router, the interval-capture `SessionManager`, the `seen` CLI, and the
`seen mcp` stdio MCP server — all conforming to `docs/api.md`, fully tested
via `swift run SeenTests`.

## 2. CONTEXT

- You are in an isolated git worktree of `~/projects/seen` on branch
  `delegate/cline-api`. Work only here.
- **Read first:** `ARCHITECTURE.md`, `docs/api.md` (the contract you
  implement — conform exactly), and `Sources/SeenKit/Domain/` — Domain is the
  **frozen contract**; never edit Domain files or `Package.swift`
  (swift-argument-parser is already declared for `seen-cli`). If a Domain type
  blocks you, escalate (§4).
- Toolchain: Swift 6.3, Command Line Tools only. **No XCTest / `swift test` /
  xcodebuild.** Build: `swift build`; tests: `swift run SeenTests`
  (executable runner — see `Sources/SeenTests/TestKit.swift`).
- macOS 15+, Swift 6 strict concurrency; actors own mutable state.
- Other delegates are building the capture engine (A) and app shell (C) in
  parallel. You code against Domain protocols with your own mocks in tests.
  Your write scope (only these):
  - `Sources/SeenKit/Server/`, `Sources/SeenKit/Sessions/`
  - `Sources/seen-cli/` (replace the stub; keep the `seen` command name)
  - `Sources/SeenTests/APITests.swift`
  - one line in `Sources/SeenTests/AllTests.swift` registering `apiTests`

### What to build

1. **`Server/HTTPMessage.swift`** — minimal HTTP/1.1 types + codec:
   `HTTPRequest` (method, path, headers, body) parsed incrementally from bytes
   (request line, headers, `Content-Length` body), `HTTPResponse` (status,
   JSON body) serialized to bytes. No pipelining needed; `Connection: close`
   semantics are fine.
2. **`Server/UDSHTTPServer.swift`** — listens on `SeenPaths.socketPath`.
   `NWListener` with a Unix endpoint, or BSD sockets + DispatchSource if NW
   fights you (implementation detail is yours; behavior is the contract).
   Must: create the parent directory, unlink a stale socket file on start,
   `chmod 0600` the socket, hand parsed requests to the router, and support
   clean `start()`/`stop()`.
3. **`Server/APIRouter.swift`** — pure request→response mapping (testable
   without sockets):
   ```swift
   public struct APIRouter: Sendable {
       public init(
           coordinator: any CaptureCoordinating,
           sessions: any SessionManaging,
           capturer: any ScreenCapturing,
           configurationProvider: @escaping @Sendable () -> CaptureConfiguration
       )
       public func handle(_ request: HTTPRequest) async -> HTTPResponse
   }
   ```
   Endpoints, payloads, and the error→status mapping exactly per `docs/api.md`.
   `SeenError` → its `code`/`message`; unexpected errors → 500 `internal`.
4. **`Server/JSONCoding.swift`** — shared `JSONEncoder`/`JSONDecoder`
   factories (`.iso8601` dates) used by server, CLI, and MCP.
5. **`Server/APIClient.swift`** — `protocol SeenAPIClient` (async methods
   mirroring the endpoints) + `UDSAPIClient` implementation speaking HTTP over
   the socket via `NWConnection` (or BSD sockets). CLI and MCP share this;
   tests mock the protocol.
6. **`Sessions/SessionManager.swift`** —
   ```swift
   public actor SessionManager: SessionManaging {
       public init(
           coordinator: any CaptureCoordinating,
           eventSink: @escaping @Sendable (CaptureEvent) -> Void = { _ in },
           sleep: @escaping @Sendable (TimeInterval) async throws -> Void
               = { try await Task.sleep(for: .seconds($0)) }
       )
   }
   ```
   - `start`: `SessionLimits.validate` + reject when
     `activeSessions().count >= SessionLimits.maxConcurrentSessions`; then run
     a `Task` loop: capture immediately, then every `interval` until duration
     elapses, `maxCapturesPerSession` is hit, or `stop(id:)`.
   - Emit `.sessionStarted` / `.sessionEnded` through `eventSink`. Individual
     capture failures don't kill the session, but **3 consecutive failures
     abort it** (prevents spinning on `permission_required`).
   - `sleep` is injected so tests run instantly.
7. **`seen` CLI** (ArgumentParser, replaces the stub):
   - `seen health`, `seen targets [--json]`
   - `seen capture [--app N|--display I|--window I] [--image-only|--ocr-only]
     [--format F] [--quality Q] [--max-dimension N] [--json]` — human output:
     saved paths + OCR text; `--json`: raw `CaptureResult`.
   - `seen watch start --interval T --duration T [target flags]` /
     `seen watch list` / `seen watch stop <id>` — accept `10s` / `5m` suffixes
     (bare number = seconds).
   - `seen open` — `GET /config`, then `/usr/bin/open <saveDirectory>`.
   - `seen mcp` — the MCP server (below).
   - Daemon unreachable → clear message ("Seen isn't running — launch the Seen
     app") and nonzero exit.
8. **MCP server (`Sources/seen-cli/MCP/`)** — stdio, newline-delimited
   JSON-RPC 2.0, hand-rolled (no new dependencies):
   - `initialize` → `{protocolVersion: "2025-06-18", capabilities: {tools: {}},
     serverInfo: {name: "seen", version: Seen.version}}`;
     `notifications/initialized` ignored; `ping` → `{}`; unknown → `-32601`.
   - `tools/list` / `tools/call` for the 5 tools in `docs/api.md` §MCP
     (`capture_screen`, `list_targets`, `start_watch`, `stop_watch`,
     `watch_status`), string targets `"all" | "display:<id>" | "app:<name>" |
     "window:<id>"` translated to `CaptureRequest.Target`.
   - `capture_screen` reads the saved files and returns base64 `image` content
     blocks (with mimeType) when output includes image, plus a `text` block
     with OCR text and saved paths.
   - API/daemon failures → tool result with `isError: true` and a helpful
     message, never a crashed process.
   - Structure message handling as a testable
     `MCPHandler(client: any SeenAPIClient).handle(_ message: Data) async -> Data?`
     so tests drive it without stdio.

### Tests (`apiTests`)

Mock `CaptureCoordinating`/`SessionManaging`/`ScreenCapturing`/`SeenAPIClient`.
Must cover at least:
- HTTP codec: parse request with body split across chunks; serialize response.
- Router: every endpoint's happy path + error mapping (`permission_required`
  → 403, `session_not_found` → 404, bad JSON → 400, unexpected → 500).
- SessionManager (instant `sleep`): capture count over a session, early stop,
  concurrent-session cap, limits rejection, 3-consecutive-failure abort,
  events emitted.
- End-to-end: start `UDSHTTPServer` on a socket in a temp dir (set the path
  via `SEEN_SOCKET` semantics or direct init), hit `/health` and `/capture`
  with `UDSAPIClient` against mocks, assert payloads; verify socket file mode
  is 0600 and a stale socket is replaced.
- MCP: initialize handshake, `tools/list` shape, `capture_screen` returning
  image+text blocks (use a tiny real file in a temp dir), error → `isError`.

## 3. DEFINITION OF DONE

I will run these exact commands myself in your worktree:

1. `swift build` exits 0 with no new warnings.
2. `swift run SeenTests` exits 0 and lists your `apiTests` cases.
3. `swift run seen --help` exits 0 and shows the subcommands.
4. `git status --porcelain` clean; `git diff main --stat` touches only your
   allowed paths (§2).
5. Public API doc-commented; conforms to `docs/api.md` exactly (I will diff
   behavior against the doc).

## 4. ESCALATION — stop and ask instead of guessing when:

- `docs/api.md` or a Domain type is ambiguous/contradictory or doesn't fit
  (never edit Domain; the API doc is mine to amend — propose, don't change).
- Same failure ≥2–3 attempts (e.g. NWListener UDS quirks) — describe what you
  tried before switching strategy wholesale.
- Anything needs network access, new dependencies, GUI, permissions, or files
  outside your scope.

## 5. REVERSE CHANNEL

To reach me, run ONE command from your worktree:
- `./.delegate/notify needs-input "the question or decision you need answered"`
- `./.delegate/notify blocked "what you are stuck on"`
- `./.delegate/notify done "summary of what you finished"`

then STOP AND WAIT at your prompt — do not exit, do not continue. I will
review your work and either confirm you're done or send corrections. After I
reply, run `./.delegate/notify resume` BEFORE continuing — otherwise your
status stays stuck.

## 6. OUTPUT

Commit to your branch in small, descriptive commits. When the Definition of
Done is green, run `./.delegate/notify done "<one-paragraph summary>"` and
wait at your prompt.

## 7. SCOPE BOUNDARY

Stay inside your worktree. No pushing, PRs, installs, GUI launches, permission
prompts, or new package dependencies. Do not modify `Sources/SeenKit/Domain/`,
`Package.swift`, `Sources/SeenKit/{Capture,OCR,Imaging,Storage,Coordinator}/`,
`Sources/SeenApp/`, or `docs/api.md`.
