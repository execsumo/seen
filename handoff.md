# Seen — Handoff

_Last updated: 2026-07-25. Read this before making changes._

## Status: v0.1.0 — **shipped** 2026-07-25

Notarized DMG published, Homebrew cask live in `execsumo/homebrew-tap`,
`brew install --cask seen` resolves. The README's install instructions are now
true. See "Release status" below for what the first real release proved.

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

1. Real ScreenCaptureKit captures (all-displays, app-target, window-target).
2. The permission onboarding flow and deep links.
3. Hotkey → push pipeline end-to-end (command template / tmux / clipboard).
4. Menu bar icon state transitions driven by real events.
5. MCP registered in a real agent (`claude mcp add seen -- seen mcp`) —
   inline image blocks rendering in an actual session.
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

### 1. Quit-and-reopen after the Screen Recording grant (highest value)

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

## Known rough edges / next work

- ~~**Ship v0.1.0**~~ — done 2026-07-25; see "Release status" above.
- **`scripts/dmg.sh:6` defaults `NOTARY_PROFILE="heard-notary"`** — a leftover
  from the Heard project. Harmless on the CI path (the workflow passes
  `--api-key-path`, so `NOTARY_AUTH` takes the API-key branch), but a *local*
  `dmg.sh` run without `--api-key-path` reaches for a keychain profile named
  after a different app. Rename when convenient.
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
