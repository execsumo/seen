# Seen — Handoff

## Status

**v0.1.3 is shipped and re-cut.** There is no known blocking work or required
feature work remaining.

**In flight:** branch `design/terminal-brutalism` restyles the whole UI to the
"High-Performance Terminal" system in `DESIGN.md`. It builds clean and the
tests pass — see "Resume here" below for what is and isn't confirmed.

The project is a macOS 15+ menu-bar app that captures screenshots and OCR, and
exposes them to AI tools through MCP, a CLI, or raw HTTP over a per-user Unix
socket.

## Verified

- 67/67 headless tests pass; builds were clean with zero warnings.
- Release workflow, signing, notarization, Homebrew cask publication, and DMG
  checksums were verified for v0.1.3.
- MCP works end-to-end over stdio, including inline image results.
- Screen Recording permission onboarding and the quit/reopen flow were tested
  against a real grant cycle.
- All-display and window-target captures work. App-target capture is the only
  capture target not explicitly verified in a live run.
- `seen setup` supports Claude Code, Codex, Cursor, and Antigravity, including
  MCP configuration merging and skill installation.
- The working tree was clean on `main` at the last handoff review.

## Resume here — `design/terminal-brutalism`

The 2026-08-29 restyle to `DESIGN.md` was authored on Linux, where the macOS SDK
does not exist, so it has never been type-checked, linked, or rendered.

**What changed**

- `SeenApp/DesignSystem.swift` rewritten: the old "Paper" language is gone.
  Dark-only palette, JetBrains Mono type scale, 1px borders, 0px radii, tonal
  depth instead of shadows. New components: `StatusTag` (was `StatusPill`),
  `HRule`, `InfoNote`, `CommandLineText`, `BlockCursor`, `Marker`,
  `TerminalSegmented`, `Terminal{Primary,Secondary}ButtonStyle` (were
  `Paper*ButtonStyle`), `MenuBarRowLabel`.
- `MenuContent`, `SettingsView`, `OnboardingView`, `SeenApp` updated to match.
  Windows were widened for mono's advance: menu 280→340, settings 660×480→720×540,
  onboarding 420×340→460×440.
- `Picker(.segmented)` in Destination replaced by `TerminalSegmented` — the
  system control cannot be squared off. Same binding, same three options.
- `NSApplication.appearance` pinned to `.darkAqua`; each root view also sets
  `.preferredColorScheme(.dark)`.
- JetBrains Mono Regular/Medium/SemiBold/Bold (OFL 2.304) added under
  `Sources/SeenApp/Resources/Fonts`, declared via `.copy` in `Package.swift`,
  and copied to `Contents/Resources/Fonts` by `scripts/bundle.sh`. `SeenFonts`
  registers them with `CTFontManagerRegisterFontsForURL` at first font
  resolution and falls back to the system monospace face if they are missing.

**Verified**

- **On macOS (Darwin 25.5.0, arm64):** `swift build` completes clean — no
  errors, no warnings — and `swift run SeenTests` is 67/67. The restyle
  type-checks and links.
- On Linux, where the branch was authored: `swiftc -parse -swift-version 6`
  over `Sources/SeenApp` is clean, `Package.swift` parses, `bash -n
  scripts/bundle.sh` passes.
- A mechanical conformance check against `DESIGN.md` passes 29/29 — every
  colour in the token block traces to a value in `DESIGN.md`, every named type
  step matches the spec's frontmatter (size, weight, line height, letter
  spacing), spacing sits on the 4px baseline, and there is no `cornerRadius`,
  `RoundedRectangle`, `Capsule`, `.shadow`, or proportional font left in
  `Sources/SeenApp`.
- An intra-module check confirms all 45 `SeenTheme`/`SeenType`/`SeenFonts`
  member references resolve and all 62 call sites of the 24 in-module
  components match their synthesised memberwise initialisers.

## Non-blocking caveats

- The Developer ID auto-detection fix in `scripts/bundle.sh` landed, but has
  not been exercised locally on a real Mac. Release signing itself is verified.
- `Seen.version` is hand-maintained; update it when cutting the next release.
- `seen` human-readable output is functional but somewhat raw.
- App-target capture remains worth checking if that capture mode matters.

## Optional future enhancements

These are deliberately not required for the current release:

- Loopback HTTP/TCP support for clients that cannot use stdio or Unix sockets.
- Launch at login.
- A dedicated app icon asset.
- WebP encoding and evidence-based format checks for additional harnesses.

## Development notes

- Build and test with:
  ```sh
  swift build
  swift run SeenTests
  ```
- Build/install the app with `./scripts/bundle.sh` or use
  `./scripts/bundle.sh --no-install`.
- `docs/api.md` is the normative API/CLI/MCP contract; update it before
  changing those surfaces.
- `ARCHITECTURE.md` is the design reference.
- No Xcode project is used; Swift Package Manager and Command Line Tools are
  sufficient.
