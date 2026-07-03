# Workstream C — App Shell (menu bar UI, settings, hotkey, push pipeline)

## 1. OBJECTIVE

Implement the Seen menu bar app: dynamic-state MenuBarExtra, Settings panes,
global hotkey, the push-to-LLM pipeline, permission onboarding, and
`scripts/bundle.sh` — with all headless-testable logic covered in
`swift run SeenTests`.

## 2. CONTEXT

- You are in an isolated git worktree of `~/projects/seen` on branch
  `delegate/agy-shell`. Work only here.
- **Read first:** `ARCHITECTURE.md`, `docs/api.md`, and
  `Sources/SeenKit/Domain/` — Domain is the **frozen contract**; never edit
  Domain files or `Package.swift`. If a Domain type blocks you, escalate (§4).
- Toolchain: Swift 6.3, Command Line Tools only. **No XCTest / `swift test` /
  xcodebuild / Xcode projects.** Build: `swift build`; tests:
  `swift run SeenTests` (executable runner — see `Sources/SeenTests/TestKit.swift`).
- macOS 15+, SwiftUI, Swift 6 strict concurrency. UI state on `@MainActor`.
- **You cannot launch the app, trigger permission prompts, or verify UI
  visually here** — I do that at integration. Your job: everything compiles,
  and every piece of logic that can run headless is factored out pure and
  tested.
- Other delegates build the capture engine (A) and the server/CLI (B) in
  parallel. You code against Domain protocols only, with in-target mocks.
  Your write scope (only these):
  - `Sources/SeenKit/Push/`
  - `Sources/SeenApp/` (replace the stub)
  - `scripts/bundle.sh`
  - `Sources/SeenTests/ShellTests.swift`
  - one line in `Sources/SeenTests/AllTests.swift` registering `shellTests`

### What to build

1. **`Push/` in SeenKit** — delivering a capture to the user's LLM agent:
   - `PushDestination.swift` — `enum PushDestination: Codable, Sendable`:
     `.commandTemplate(String)`, `.tmuxPane(pane: String, template: String)`,
     `.clipboard`.
   - `PushTemplate.swift` — pure rendering: placeholders `{path}` (first saved
     file), `{paths}` (all, space-joined), `{text}` (combined OCR text).
     Values are single-quote shell-escaped for command templates. Unknown
     placeholders left untouched.
   - `ProcessRunning.swift` — `protocol ProcessRunning: Sendable { func run(_
     executable: String, _ arguments: [String]) async throws -> Int32 }` +
     default `Process`-based implementation. All external execution goes
     through this so tests can mock it.
   - `PushPipeline.swift` — given a `CaptureResult` + destination:
     command template → `/bin/zsh -lc <rendered>`; tmux → `tmux send-keys -t
     <pane> <rendered> Enter` (drops the capture into an ongoing CLI session);
     clipboard → `NSPasteboard` (paths + text).
2. **`SeenApp/`** (replace the stub wholesale):
   - `Composition.swift` — the single composition root. Build the app's
     dependency graph against Domain protocols, using local
     `PlaceholderCapturer` / `PlaceholderCoordinator` / etc. mocks so the
     target runs standalone. Mark each mock line with `// INTEGRATION-SWAP:`
     — I replace them with workstream A/B's real types at integration. Keep
     the app's SwiftUI code ignorant of concrete types.
   - `AppState.swift` — `@MainActor @Observable`: last capture time, active
     sessions, permission status; subscribes via
     `CaptureCoordinating.observeEvents` (hop to main actor in the handler).
   - `MenuBarIcon.swift` — dynamic icon with **three visually distinct
     states**: idle / recent capture (≤3 s after `.captureCompleted`) /
     interval session active (while sessions > 0). Factor state selection into
     a pure `func iconState(lastCapture: Date?, activeSessions: Int, now: Date)
     -> IconState` and test it.
   - `MenuContent.swift` — menu: Capture Now; Capture App ▸ (submenu from
     `applications()`, deduped by app); Open Screenshots Folder
     (`NSWorkspace`, current save dir); active sessions with Stop buttons;
     API status line (socket path + "Copy curl example"); Settings…; Quit.
   - `AppSettings.swift` — UserDefaults-backed `@Observable` store: save
     directory, format, quality, max dimension, hotkey (keyCode + modifiers),
     push destination, default capture output. Exposes
     `captureConfiguration` (`CaptureConfiguration`) and a
     `@Sendable () -> CaptureConfiguration` provider for injection.
     Serialization round-trip must be tested.
   - `SettingsView.swift` + panes: General (save dir via NSOpenPanel, format/
     quality/max dimension), Hotkey (recorder — capture the next keystroke via
     a local NSEvent monitor while recording), Destination (picker:
     command template with editable text + presets for claude/codex/cline/agy,
     tmux pane — populate choices by running `tmux list-panes -a -F
     "#{pane_id} #{pane_title}"` through `ProcessRunning`, clipboard), API
     (socket path, copyable curl example), Permissions (live Screen Recording
     status, "Request Permission" via `CGRequestScreenCaptureAccess()`, "Open
     System Settings" deep link
     `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`).
   - `HotkeyManager.swift` — Carbon `RegisterEventHotKey` wrapper (no
     third-party deps), re-registers when the setting changes; sensible
     default (e.g. ⌃⌥⌘S). On press: `coordinator.perform` with the settings'
     default request, then `PushPipeline` to the configured destination.
   - `OnboardingView.swift` — first-launch/permission-missing window
     explaining the Screen Recording prompt with the request + deep-link
     buttons and live status re-check.
3. **`scripts/bundle.sh`** — build a `Seen.app` bundle and install to
   /Applications. You may read `~/projects/Heard/scripts/bundle.sh`
   (READ-ONLY, outside your worktree) as the reference pattern; adapt for
   Seen: `LSUIElement` true (menu bar only), same stable-signing behavior
   (`--sign` identity flag, Developer ID / "Dev Cert" auto-detect, ad-hoc
   fallback). **Never execute it here** — it installs and relaunches an app.

### Tests (`shellTests`)

- Template rendering: each placeholder, shell-escaping of spaces/quotes,
  multiple paths, unknown placeholder untouched.
- PushPipeline with a mock `ProcessRunning`: command template invokes zsh
  with the rendered string; tmux destination sends to the right pane.
- Icon state function: idle vs recent vs session-active precedence
  (session-active wins over recent), 3-second expiry boundary.
- AppSettings: round-trip through a scratch `UserDefaults(suiteName:)`,
  defaults when empty, `captureConfiguration` reflects stored values.

## 3. DEFINITION OF DONE

I will run these exact commands myself in your worktree:

1. `swift build` exits 0 with no new warnings.
2. `swift run SeenTests` exits 0 and lists your `shellTests` cases.
3. `bash -n scripts/bundle.sh` exits 0 (syntax only — never execute it).
4. `git status --porcelain` clean; `git diff main --stat` touches only your
   allowed paths (§2).
5. Public types doc-commented; no concrete engine/server types referenced
   outside `Composition.swift`.

## 4. ESCALATION — stop and ask instead of guessing when:

- A Domain protocol doesn't expose something the UI needs (never edit Domain).
- Same failure ≥2–3 attempts (Carbon hotkey registration and @Observable +
  strict concurrency are the likely spots).
- Anything would require launching the app, granting permissions, network, or
  files outside your scope.
- A product decision isn't derivable from ARCHITECTURE.md (e.g. exact preset
  command strings — propose defaults, flag uncertainty in your done summary).

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

Stay inside your worktree (plus the read-only Heard reference above). No
pushing, PRs, installing to /Applications, launching GUI apps, permission
prompts, or new dependencies. Do not modify `Sources/SeenKit/Domain/`,
`Package.swift`, `Sources/SeenKit/{Capture,OCR,Imaging,Storage,Coordinator,Server,Sessions}/`,
or `Sources/seen-cli/`.
