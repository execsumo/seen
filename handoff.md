# Seen — Handoff

_Last updated: 2026-07-25. Read this before making changes._

## Status: v0.1.3 — **shipped** 2026-07-25 (run `30174165770`)

Contains the `seen setup` command group, the quit-and-reopen permission flow,
and MCP protocol-version negotiation. 59/59 tests, zero warnings.

**The Screen Recording gate is closed** — a real grant cycle was walked
2026-07-25 and the relaunch behaved. See "TCC walkthrough result" below.

### Release status — v0.1.3

Verified independently after the run, not taken on trust:
- Run `30174165770`: `test / build-and-test` **success** → `release` **success**.
- Release `v0.1.3` published, asset `Seen-0.1.3.dmg` (1,279,181 bytes).
- DMG sha256 `342a5d1c…b981` identical across three places: the downloaded
  asset, `Casks/seen.rb` on `main` (bot commit `3a93234`), and the tap.
- `xcrun stapler validate` passes on **both** the DMG and the app inside it;
  `spctl --type open` (DMG) and `--type execute` (app) both
  `accepted, source=Notarized Developer ID`;
  `Authority=Developer ID Application: Herwin Gill (577WHA43TF)`.
- Shipped bundle checked against the v0.1.1 lesson: `CFBundleShortVersionString`
  0.1.3, SwiftUI discriminator **1 for the app / 0 for the CLI** (so the two
  executables are distinct — no overwrite), `SKILL.md` present in
  `Contents/Resources/seen-skill/`.
- `brew info --cask execsumo/tap/seen` → 0.1.3.

**This run also proved the `build/` untracking is safe.** `be9baee` removed
`build/Seen.app` from git (it had been committed by accident in `a31e99c`), and
the release went green afterwards — `bundle.sh` recreates the directory, so the
workflow never depended on the tracked artifacts. That was the riskiest part of
the commit and it is now empirically settled.

### 2026-07-25 MCP protocol version is negotiated, not hardcoded

`initialize` used to answer `"2025-06-18"` unconditionally, whatever the client
asked for. Per the MCP spec that reads as *"I do not support your version"*, and
a strict client is entitled to disconnect — it was answering `2025-06-18` to a
`2024-11-05` request. Now `MCPHandler.negotiateProtocolVersion` echoes the
requested version when it's in `supportedProtocolVersions`
(`2024-11-05` / `2025-03-26` / `2025-06-18`) and falls back to the latest when
the request is unknown or omits the field.

**It's an allowlist, not an echo** — echoing whatever arrives would claim
support for versions that don't exist. The list is wide only because nothing in
the handler varies by version; a version that *does* change behavior needs a
branch here, not another array entry. Verified live over stdio for all three
supported versions plus an unknown one and a no-params request.

**`Seen.version` is hand-maintained and was stale.** It sat at `"0.1.0"` through
v0.1.1 and v0.1.2, so `GET /health` and MCP `serverInfo.version` reported 0.1.0
from every build. Nothing derives it from the git tag or the bundle version —
**bump `Sources/SeenKit/Domain/Seen.swift` as part of cutting a release.**

### 2026-07-25 TCC walkthrough result — the gate is closed

The revoke/grant cycle was finally walked against a `bundle.sh` install
(0.1.3-dev, Dev Cert). Both failure modes the design worried about were checked
and neither occurred:
- **Not "app not running":** PID went 248 → 291 across the relaunch.
- **Not "two live instances":** `pgrep -fl Seen` returned exactly one, and
  `seen health` answered on the UDS — so no stale-socket theft.
- `screenRecordingPermission` flipped to `true` after the grant.
- `LSUIElement` did not interfere with the relaunch.

**Then the MCP path was exercised end to end for the first time**, driving the
real stdio transport with JSON-RPC (`initialize` → `tools/list` →
`tools/call capture_screen`): a valid **1568×1020 PNG** came back in an `image`
block and rendered inline in an agent session, with the OCR text and saved path
in the companion `text` block. 1568 confirms the agent default applies and
`HumanCapture`'s 2048 policy is not leaking into the agent path.

Note the signing identity changed ad-hoc → Dev Cert on that install, which is
why the grant reset. A Homebrew install is Developer ID signed, so it resets
once more — that is expected, not a regression.

### 2026-07-25 v0.1.1 was broken on arrival — fixed in v0.1.2
**v0.1.1's app bundle could not launch.** macOS filesystems are
case-insensitive, so `cp "$CLI" "$APP/Contents/MacOS/seen"` resolved to
`Contents/MacOS/Seen` and **overwrote the GUI executable with the CLI**. The
shipped bundle had exactly one binary; `CFBundleExecutable` pointed at it, so
double-clicking Seen.app ran a CLI that printed usage and exited. No menu bar
item, no socket, no MCP — strictly worse than v0.1.0's missing CLI.

Fixes in v0.1.2:
- CLI moved to `Contents/Resources/bin/seen` (no case collision); cask `binary`
  stanza updated to match.
- `bundle.sh` now `cmp`s both copied payloads against their source binaries and
  aborts if either differs, so an overwrite can never ship silently again.
- `bundle.sh --no-install` added: it used to clobber `/Applications/Seen.app`
  unconditionally, which made the bundler untestable without wrecking the
  installed app and its TCC grant.

**How it got through:** the pre-release check ran the *CLI* out of the bundle
and confirmed it worked. It never checked that the app binary survived — the
test covered the thing being added, not the thing being broken. When verifying
a bundle, identify **both** executables. Note `strings` is useless for this
(Swift literals don't surface) and AppKit is not a discriminator (the CLI links
it transitively for pasteboard access). Use SwiftUI linkage:
`otool -L … | grep -c SwiftUI` is >0 for the app, 0 for the CLI.

### 2026-07-25 CLI now ships with the app (v0.1.1, corrected in v0.1.2)
**v0.1.0 shipped without the `seen` CLI, so MCP cannot work for anyone who
installed via Homebrew.** `bundle.sh` built only `--product SeenApp` and the
cask had only an `app` stanza, so the binary that *is* the MCP transport
(`seen mcp` is a stdio shim over the socket) shipped nowhere — while
`SKILL.md` told agents to run `claude mcp add seen -- seen mcp`. Fixed on
`main`, **not yet released**:
- `bundle.sh` builds both products and copies the CLI into the bundle. (It
  originally landed at `Contents/MacOS/seen`, which is what broke v0.1.1; the
  live path is `Contents/Resources/bin/seen`.)
- Signing is now **inside-out** — the nested `seen` binary is signed before the
  bundle, or the outer signature seals an unsigned executable and notarization
  rejects the app. Verified in a scratch bundle: `codesign --verify --deep
  --strict` passes, the nested binary verifies independently, and it runs.
- `Casks/seen.rb` gained a `binary` stanza so brew symlinks the CLI onto PATH
  (now pointing at `Contents/Resources/bin/seen`).
- README reordered (CLI first, then MCP, then raw HTTP) because MCP depends on
  the CLI; raw HTTP over the socket is the only door needing nothing installed.
- Cursor documented alongside Claude Code: no CLI equivalent to
  `claude mcp add`, so it's `~/.cursor/mcp.json` / `.cursor/mcp.json` with
  `{"mcpServers":{"seen":{"command":"seen","args":["mcp"]}}}`.

**Watch out for stale installs.** `/Applications/Seen.app` is only rebuilt by
`./scripts/bundle.sh`, and a hand-copied `seen` on PATH never updates at all.
Both drift silently from `main` — a build from before `b07110f` still shows the
deleted "Agent Access" pane and the `Copy “claude mcp add” command` menu row.
Check `ls -l /Applications/Seen.app/Contents/MacOS/` against `git log` before
concluding the app disagrees with the code.

**Before installing v0.1.1 via brew, delete any hand-copied `seen` on PATH**
(`rm /opt/homebrew/bin/seen` or `/usr/local/bin/seen`). The old README told
people to `cp .build/debug/seen /usr/local/bin/`, and Homebrew refuses to
overwrite a non-cask file at the path its `binary` stanza wants to symlink —
the install aborts, and it looks like the cask is broken rather than a local
leftover.

Also note `bundle.sh` builds the two products in **separate** `swift build`
invocations: SwiftPM's `--product` is last-wins, so
`--product SeenApp --product seen` silently builds only `seen` and the script
then fails its own missing-binary guard. Nothing in CI would catch that —
`ci.yml` runs a plain `swift build` (all products) and no workflow exercises
`bundle.sh` until a tag triggers `dmg.sh`.

### 2026-07-25 CI added; release gated on it
- **`.github/workflows/ci.yml`** (new) — `swift build` + `swift run SeenTests`
  on every push/PR to `main`, macos-15. Everything in the suite is headless
  (no Screen Recording grant, no windows), so it runs unattended. Verified
  locally before writing: clean build, **38/38 pass**.
- **`release.yml` now gates on it** — CI is exposed via `workflow_call` and the
  `release` job `needs: test`, so a broken suite fails before the workflow
  touches signing secrets or burns a notarization slot.
- The cask bot commit no longer carries a skip-CI override; `ci.yml` instead
  uses `paths-ignore` for `Casks/**`, `docs/**`, `**.md`, `LICENSE`. Same zero
  runs for a sha-only rewrite, but a bot commit that ever touched Swift is
  gated rather than silently skipped. Path filters don't apply to
  `workflow_call`, so the release gate is unaffected.
- Two Actions traps worth remembering: **YAML anchors are not supported** in
  workflow files (the ignore list is spelled out per trigger), and the skip-CI
  token is honored **anywhere in a commit message, body included** — a commit
  merely describing it will skip its own run.

### Release status — v0.1.0 shipped 2026-07-25 (run `30164772743`)

**Why it needed a retry.** `v0.1.0` was tagged 2026-07-08, but the Release run
(2026-07-09 05:35, id `28996583823`) was **cancelled** — the signing secrets
landed *minutes after* it started (`GH_PAT` 05:41, `APPLE_API_KEY*` 05:46–05:48,
cert/password/Developer ID 05:58–06:02). Nobody re-triggered, so for two weeks
`main` advertised a `brew install` that could not resolve.

**How it was retried.** The tag was retargeted from `5ea00ef` to `70c5f0e` (the
commit adding the CI gate) by deleting and re-pushing it. Note for next time:
`workflow_dispatch` **cannot** re-run an existing version — "Resolve release
version" hard-exits with `ERROR: tag v${VERSION} already exists`. Delete +
re-push the tag (fires `push: tags:['v*']`), or bump the version.

**Verified independently after the run** (not taken on trust):
- Run `30164772743`: two jobs, `test / build-and-test` **success** → `release`
  **success**. The CI gate genuinely fires on a tag push via `workflow_call`.
- Release `v0.1.0` published, asset `Seen-0.1.0.dmg`.
- DMG sha256 `7f2086be…6275` matches `Casks/seen.rb` on `main` (bot commit
  `1e8c467`) **and** `execsumo/homebrew-tap`.
- `xcrun stapler validate` → ticket valid; `spctl --assess --type open` →
  `accepted, source=Notarized Developer ID`.
- `brew info --cask execsumo/tap/seen` → 0.1.0.

**The whole tail of the workflow ran for the first time here** — upload release,
rewrite the cask sha, commit to `main`, push to the tap. It works end to end;
it is no longer untested.

## Earlier status: feature-complete, integrated, UX redesign done, verified live

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

1. ~~Real ScreenCaptureKit captures~~ — **all-displays verified 2026-07-25** via
   the MCP walkthrough. App-target and window-target still unverified.
2. ~~The permission onboarding flow~~ — **verified 2026-07-25** (see "TCC
   walkthrough result"). Deep links still unverified.
3. Hotkey → push pipeline end-to-end (command template / tmux / clipboard).
4. Menu bar icon state transitions driven by real events.
5. ~~MCP inline image blocks rendering in an actual session~~ — **verified
   2026-07-25** by driving `seen mcp` over stdio. The one step not exercised is
   `claude mcp add seen -- seen mcp` registration itself; everything downstream
   of it is confirmed.
6. WebP encoding on this OS version (test asserts encode-or-clean-error).

### 2026-07-25 Human captures get 2K; harness formats now tracked with dates
- **`AppCore/HumanCapture`** (new) is the single policy for hotkey + menu bar
  captures: longest edge **2048 px**, format left nil so PNG still applies.
  Both call sites (`HotkeyManager.swift`, `MenuContent.swift`) previously built
  a bare `CaptureRequest()`, which fell through to the 1568 px agent default —
  so a person grabbing their own 5K screen got an image shrunk to fit
  Anthropic's token budget, for no reason. It stays a cap rather than native
  resolution so a multi-display grab can't put a ~100 MB PNG on the pasteboard.
  Covered by 2 tests in `ShellTests.swift` (40/40 green).
- **`docs/harness-formats.md`** (new) carries a **Last updated** date and a
  per-harness table. Only the Claude row is evidence-based (jpeg/png/gif/webp,
  no heic/avif, billed by dimensions); Cursor / Codex / Cline / Gemini-backed
  rows are explicitly marked *Unverified* rather than left blank, so the gaps
  are visible. Includes the procedure for verifying a row.
- **WebP is called out as not supported**, with the two conditions that should
  trigger an evaluation (macOS gains an encoder or we accept a `libwebp`
  dependency, **and** a harness measurably benefits). Notes the trap: for Claude
  the win would be bytes, but billing is by dimensions, so a smaller file may
  buy literally nothing. Not to be built now.
- Stale docs fixed: `ARCHITECTURE.md` filename example said `.jpg` (PNG since
  `b07110f`), and `docs/api.md` — the *normative* contract — omitted the
  `format?` argument on `capture_screen`, so agents reading it couldn't learn
  they may request JPEG. Verified against `MCPHandler.swift:44-45,120-121`
  before documenting.

## Setup friction: three fixes worth making (identified 2026-07-25)

Setup is close to effortless — install is one command, MCP is one command — but
three spots still cost the user something. **#1 is the only one that makes a
correctly-installed app look broken**; do it first. #2 and #3 are polish and
share an implementation (a new `seen setup` command group), so they're cheap
together.

**Status: all three shipped to `main` 2026-07-25** — `seen setup claude` /
`cursor` / `skill` (#2, #3) and the quit-and-reopen phase + relaunch button (#1).
57/57 tests, zero warnings, nothing pushed. The sections below are kept for the
design rationale; each ends with what actually landed.

**The one thing still outstanding: nobody has run a real Screen Recording
revoke/grant cycle against #1.** It is the only part of this work that no test
can reach. See "Where this stands" at the end of #1.

### The `argv[0]` lesson — read before writing any CLI path resolution

`seen setup skill` locates `SKILL.md` relative to its own executable. The first
implementation used `CommandLine.arguments[0]`, which passed every test and would
have **failed for every Homebrew user**: when the shell resolves a command via
`PATH`, `argv[0]` is the bare word `seen`, not a path, so `fileURLWithPath`
resolves it against the *current directory*. Every test invoked the binary by an
explicit path (`.build/debug/seen`), so nothing caught it.

Use `Bundle.main.executableURL` (backed by `_NSGetExecutablePath`, correct
regardless of `argv[0]`), then `resolvingSymlinksInPath()` — Homebrew users come
through `/opt/homebrew/bin/seen` → `Contents/Resources/bin/seen`, and an
unresolved symlink sends the lookup to `/opt/homebrew/seen-skill/`.

This is the **same failure shape as v0.1.1**: the test covered the thing being
added, not the invocation a user actually types. When verifying anything that
resolves paths from its own location, test it the way a user runs it — bare name
found on `PATH`, from an unrelated working directory, through the installed
symlink, on a bundle built by `bundle.sh`.

### 1. Quit-and-reopen after the Screen Recording grant (highest value)

> **STATUS 2026-07-25: shipped to `main`, but NOT verified against a real TCC
> revoke/grant cycle — that walkthrough is the one thing still outstanding.** See
> "Where this stands" at the end of this section.

**The problem.** macOS does not apply a newly-granted Screen Recording
permission to an already-running process. The user clicks Grant, approves in
System Settings, returns to Seen — and Seen still says permission is missing,
because `CGPreflightScreenCaptureAccess()` keeps returning false until the
process restarts. Nothing on screen tells them to relaunch, so the reasonable
conclusion is "this is broken."

**Where it lives.** Two surfaces do the same thing and both need the fix:
- `Sources/SeenApp/OnboardingView.swift:80-83` — "Grant Permission" button:
  `CGRequestScreenCaptureAccess()` then `composition.appState.recheckPermission()`.
- `Sources/SeenApp/SettingsView.swift:361-364` — the "Grant…" button in
  `PermissionsPane`, identical pair of calls.

`recheckPermission()` is `Sources/SeenKit/AppCore/AppState.swift:49-51` and is
just `hasPermission = CGPreflightScreenCaptureAccess()`. Both views also poll it
on a 1 s timer (`OnboardingView.swift:93`, `SettingsView.swift:382`), so the UI
faithfully reports "not granted" forever. The onboarding's only reassuring copy
("You can close this window — Seen lives in your menu bar", line 66) renders
*only* in the granted branch, so a stuck user never sees any guidance at all.

**What to build.** Track a third state beyond granted/not-granted: *requested
but not yet effective*. Set a flag when the Grant button runs
`CGRequestScreenCaptureAccess()` and it returns false (or when preflight is
still false ~2 s later). In that state, replace the Grant button with a
prominent **"Quit and Reopen Seen"** button plus one line of copy: *"macOS needs
Seen to restart before it can see your screen."*

**The relaunch itself — read this before writing it.** The obvious
implementation (`Process` running `/bin/sh -c "sleep 1; open …"`) is a **trap in
this specific codebase.** TCC attributes a child process's permission prompts to
its parent, which is exactly the bug the 2026-07-08 permission hardening fixed:
`Sources/SeenKit/Push/ProcessRunning.swift:13-27` dlsym's
`responsibility_spawnattrs_setdisclaim` and `posix_spawn`s with it precisely so
spawned agents own their own prompts. A naive relaunch helper reintroduces the
problem this app worked hard to eliminate. Two acceptable routes:
- **Preferred:** `NSWorkspace.shared.openApplication(at:configuration:)` against
  `Bundle.main.bundleURL` with `createsNewApplicationInstance = true`, then
  `NSApp.terminate(nil)` in the completion handler. This goes through
  LaunchServices rather than forking a child under Seen.
- **Fallback:** reuse `DefaultProcessRunner`'s disclaiming spawn rather than
  hand-rolling a `Process`.

Test both orderings — terminating before the new instance is registered can race
and leave the app not running at all. Also confirm `LSUIElement` (set true in
`bundle.sh`'s generated Info.plist) doesn't suppress the relaunch.

**How to verify.** This needs a real revoke/grant cycle, which is destructive to
the developer's own working grant — budget for that. Remove Seen from System
Settings → Privacy & Security → Screen Recording, relaunch, and walk the flow.
There is no headless test for this; `SeenTests` can cover the state machine
(a pure "requested but not effective" predicate in `AppCore`) but not the TCC
behavior itself. Put the predicate in `AppCore` so it *is* testable, and keep
the view dumb.

### Where this stands (2026-07-25)

**What shipped.**
- **`Sources/SeenKit/AppCore/PermissionPhase.swift`** — `PermissionPhase`
  (`needed` / `requestedPendingRestart` / `granted`) plus a pure
  `resolvePermissionPhase(granted:requestedAt:now:)`. No `CoreGraphics` inside, so
  it's headlessly testable; 5 cases in `Sources/SeenTests/PermissionPhaseTests.swift`.
- **The self-clearing rule is the load-bearing design decision:** `granted == true`
  returns `.granted` unconditionally, so the existing 1 s poll recovers on its own
  if macOS ever applies a grant live. That is what makes the relaunch button safe
  to ship *without* having run the destructive TCC test — the UI can't strand a
  user who is actually granted. Don't "optimize" that branch away.
- 2 s threshold before showing the restart button, so it doesn't flash while the
  user is still dealing with the system dialog.
- **`AppState`** gained observable `permissionPhase` + `markPermissionRequested()`;
  `recheckPermission(now:)` recomputes both. `hasPermission` is unchanged for
  existing readers.
- **`Sources/SeenApp/RelaunchHelper.swift`** — `NSWorkspace.shared.openApplication`
  against `Bundle.main.bundleURL` with `createsNewApplicationInstance = true`.
  `NSApp.terminate` fires **only** in the completion handler's success branch; on
  error it does not terminate and surfaces manual-quit copy instead. The button
  disables after one tap.
- Both views (`OnboardingView`, `SettingsView`'s `PermissionsPane`) render a
  "Quit and Reopen Seen" button in the pending phase, a "Restart Needed" pill, and
  copy in **every** phase — previously the only reassuring line rendered solely in
  the granted branch, so a stuck user saw nothing.
- **"Open System Settings" also counts as a request.** Only wiring the Grant
  button left the original bug fully intact for anyone who granted directly in
  System Settings — the path macOS's own flow pushes people down. Because that
  click doesn't prove a grant happened, the copy is worded to be true either way:
  *"If you've already allowed Seen in System Settings, it needs to restart…"*

**What is NOT verified — do this before claiming the fix works.** Nobody has run a
real revoke/grant cycle. Remove Seen from System Settings → Privacy & Security →
Screen Recording, relaunch, and walk both surfaces. Two failure modes to watch
that no test can reach:
1. **App not running at all** — terminate racing ahead of the new instance being
   registered.
2. **Two live instances** — if terminate silently fails, the second instance's
   stale-socket replacement steals the UDS from the first. Check `seen health`
   and `pgrep -fl Seen` after the relaunch, not just that a menu bar icon exists.

Also unconfirmed: whether `LSUIElement` (true in `bundle.sh`'s generated
Info.plist) affects focus behavior on relaunch for a menu-bar-only app. It should
not block the relaunch itself.

### 2. `seen setup cursor` — stop making people hand-edit JSON

**The problem.** Claude Code users run one command. Cursor users must create
`~/.cursor/mcp.json` by hand (verified 2026-07-25 against Cursor's docs: there
is no `mcp add` CLI equivalent), and a malformed file fails silently — Cursor
just doesn't show the tools.

**What to build.** A `Setup` command group in
`Sources/seen-cli/SeenCommand.swift`. Subcommands are registered in the
`CommandConfiguration` at lines 7-13; add `Setup.self` to that array and follow
the existing `AsyncParsableCommand` pattern used by `Health`, `Capture`, etc.

`seen setup cursor [--project]` should write this into `~/.cursor/mcp.json`
(or `.cursor/mcp.json` with `--project`):

```json
{ "mcpServers": { "seen": { "command": "seen", "args": ["mcp"] } } }
```

**Must merge, not overwrite.** Users have other MCP servers configured;
clobbering their file is far worse than the friction being fixed. Read the
existing JSON, insert/replace only the `seen` key, preserve everything else,
and write atomically (temp file + rename) so a crash can't truncate their
config. If the file exists but doesn't parse, refuse and say so rather than
replacing it.

Worth adding alongside: `seen setup claude` shelling out to `claude mcp add`,
so the command group covers both harnesses symmetrically.

**Convention reminder:** `docs/api.md` is normative for server/CLI/MCP and its
structure is endpoint-oriented (`## Endpoints`, `## MCP tools`). A `setup`
command touches neither the wire protocol nor the MCP tool list, so it likely
needs only a short CLI-surface note — but per the repo's rule, decide and write
the doc before the code.

### 3. `seen setup skill` — the skill install is a raw `curl`

**The problem.** README currently tells users to `mkdir` and `curl` a file into
`~/.claude/skills/seen/SKILL.md`. It works, but it's the least confidence-
inspiring step on the page.

**The non-obvious part: where does the shipped binary get `SKILL.md`?** Today it
exists only as a repo file (`.claude/skills/seen/SKILL.md`, committed) and is
**not** in the app bundle. Options, in rough order of preference:
- Have `bundle.sh` copy it into the bundle (e.g.
  `Contents/Resources/seen-skill/SKILL.md`) and have the CLI locate it relative
  to its own executable path. The CLI lives at
  `Contents/Resources/bin/seen`, so it can resolve `../seen-skill/SKILL.md`.
  Add a `cmp` guard like the binary ones so a missing file fails the build
  loudly rather than shipping a broken `setup skill`.
- Embed the contents as a generated Swift string constant at build time. No
  filesystem lookup, but adds a codegen step to a repo that currently has none.
- Fetch from GitHub at runtime. Rejected: makes a local setup command depend on
  the network, and the CLI does no networking today.

Whichever route, keep a single source of truth — the repo file — and derive the
shipped copy from it. Two hand-maintained copies will drift, exactly as the
skill's `.jpg` default drifted from the PNG switch until 2026-07-25.

### What shipped for #2 and #3 (2026-07-25)

- **`Sources/SeenKit/Setup/`** — `SetupCursor` (merge + atomic write),
  `SetupSkill` (source resolution + install), `SetupClaude` (PATH lookup + the
  argv as an asserted constant). All logic lives here, not in `seen-cli`, because
  `SeenTests` is an executable target and cannot import another executable — the
  same reason `AppCore` exists. The CLI is a thin shell: flags, default paths,
  printing, exit codes.
- **`seen setup cursor [--project] [--config <path>]`** — merges only the `seen`
  key into `~/.cursor/mcp.json`, preserves every other server, writes via temp +
  `rename`, and **refuses** a file that doesn't parse rather than replacing it.
  Re-running prints "Already configured" and rewrites nothing. `--config` exists
  so tests never touch a real config.
- **`seen setup skill [--dest <dir>] [--project] [--yes]`** — prompts for the
  destination (`~/.claude/skills` / `./.claude/skills` / another path / skip),
  gated on `isatty(STDIN_FILENO)` so it exits with a hint instead of blocking in
  a script, CI, or an agent session. Only Claude Code is offered by name: it's
  the one harness whose skills layout is verified. `~/.cursor` has `mcp.json` and
  `hooks.json` but no skills directory, so `--dest` covers everything else
  instead of inventing paths.
- **`seen setup claude`** — shells out to `claude mcp add seen -- seen mcp`.
  Prints the manual command and exits non-zero if `claude` isn't on `PATH`;
  prints claude's captured output and adds one Seen-level line on a non-zero
  exit so a duplicate-add doesn't read as Seen breaking.
  **The child must get no terminal** — null stdin, one `Pipe` for stdout+stderr,
  drained *before* `waitUntilExit()`. Foundation's `Process` spawns into a new
  process group, so an inherited tty gets the child SIGTTIN/SIGTTOU'd into `T`
  (stopped) forever and the parent's wait never returns. That shipped in v0.1.3
  as a total hang of `seen setup claude` with zero output; fixed 2026-07-25.
- **`bundle.sh`** copies `.claude/skills/seen/SKILL.md` to
  `Contents/Resources/seen-skill/SKILL.md` with a `cmp` guard, matching the two
  binary guards. Single source of truth kept: the repo file.
- **README** points Cursor users at `seen setup cursor` and the skill block at
  `seen setup skill`, keeping the hand-written JSON and the `curl` as documented
  fallbacks. `docs/api.md` gained a CLI-surface note (doc written first).
- Verification worth repeating for any change here: bare `seen` found via `PATH`
  from an unrelated cwd, on **both** a dev build and a `bundle.sh` bundle reached
  through a symlink; malformed-config refusal with the file left byte-identical;
  no-TTY exiting fast; and `setup claude` driven by a fake `claude` earlier on
  `PATH` so the real `~/.claude.json` is never touched.
  The fake `claude` must **read stdin and call `stty`**, and the whole thing must
  run under a real pty (`pty.fork`, not this shell's pipe-only stdio) — a fake
  that just prints and exits is what let the v0.1.3 hang through, because with no
  tty and nothing reading it there is no signal to stop the child.

## Known rough edges / next work

- ~~**Ship v0.1.0**~~ — done 2026-07-25; see "Release status" above.
- ~~**`scripts/dmg.sh:6` defaults `NOTARY_PROFILE="heard-notary"`**~~ — fixed
  2026-07-25; the default is now `seen-notary`. Only ever reached by a *local*
  `dmg.sh` run without `--api-key-path` (CI passes the API key, so `NOTARY_AUTH`
  takes the other branch). Note the rename doesn't create the profile: a local
  notarizing run needs `xcrun notarytool store-credentials seen-notary` first.
- **`bundle.sh:134`'s Developer ID auto-detect is dead code.** It greps for
  `'"Developer ID Application: Herwin Gill"'`, but `security find-identity`
  prints `"Developer ID Application: Herwin Gill (577WHA43TF)"` — the closing
  quote can't match, so the branch never fires and auto-detect always falls
  through to `Dev Cert`. Harmless for releases (the workflow passes `--sign`
  explicitly) but the fallback doesn't do what it claims. **Fixing it flips the
  local signing identity, which resets the Screen Recording grant** — do it
  deliberately, not in the middle of a TCC walkthrough.
- **`Seen.version` is hand-maintained** (`Sources/SeenKit/Domain/Seen.swift`) —
  bump it when cutting a release or `/health` and MCP `serverInfo` report a
  stale version, as they did through v0.1.1 and v0.1.2.
- **CLI human output** prints Swift struct dumps for `health`/`targets`/`watch
  list` instead of formatted text (see `SeenCommand.swift`) — functional, ugly.
- **Loopback TCP escape hatch** (Settings → Agent Access) is specced in
  ARCHITECTURE.md §3 but not implemented — UDS only for now.
- **App icon** is SF Symbols only; no .icns asset (menu bar uses `eye`
  variants; `SeenMark` is a drawn eye glyph used in Settings/onboarding).
- **Launch at login** not implemented (SMAppService would be the way).
- **WebP / per-harness formats** — status and the evaluation trigger now live in
  `docs/harness-formats.md` (dated). Detail below kept for the platform facts.
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
- CI (`ci.yml`) runs build+tests on every push/PR to `main`, and `release.yml`
  gates on it. A red suite blocks a release by design — fix the suite, don't
  bypass the gate.

## History notes

Built 2026-07-03 by three parallel delegate agents (herdr) against frozen
Domain protocols + spec contracts in `specs/` (kept for reference): A = capture
engine (cline), B = API surface (agy, after a first cline instance stalled),
C = app shell (agy). Integration (placeholder swap in Composition, session
event wiring, mock rename) by the orchestrator. The delegate worktrees under
`../seen-worktrees/` are historical; `main` is the source of truth.
