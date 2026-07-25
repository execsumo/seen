# Seen — Handoff

_Last updated: 2026-07-25. Read this before making changes._

## Status: v0.1.0 — **shipped** 2026-07-25

Notarized DMG published, Homebrew cask live in `execsumo/homebrew-tap`,
`brew install --cask seen` resolves. The README's install instructions are now
true. See "Release status" below for what the first real release proved.

### 2026-07-25 CLI now ships with the app (unreleased — queued for v0.1.1)
**v0.1.0 shipped without the `seen` CLI, so MCP cannot work for anyone who
installed via Homebrew.** `bundle.sh` built only `--product SeenApp` and the
cask had only an `app` stanza, so the binary that *is* the MCP transport
(`seen mcp` is a stdio shim over the socket) shipped nowhere — while
`SKILL.md` told agents to run `claude mcp add seen -- seen mcp`. Fixed on
`main`, **not yet released**:
- `bundle.sh` builds `--product SeenApp --product seen` and copies the CLI to
  `Seen.app/Contents/MacOS/seen`.
- Signing is now **inside-out** — the nested `seen` binary is signed before the
  bundle, or the outer signature seals an unsigned executable and notarization
  rejects the app. Verified in a scratch bundle: `codesign --verify --deep
  --strict` passes, the nested binary verifies independently, and it runs.
- `Casks/seen.rb` gained `binary "#{appdir}/Seen.app/Contents/MacOS/seen"` so
  brew symlinks it onto PATH.
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
