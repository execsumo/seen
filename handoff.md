# Seen — Handoff

## Status

**v0.1.3 is shipped and re-cut.** There is no known blocking work or required
feature work remaining.

**Merged:** the `design/terminal-brutalism` restyle to the "High-Performance
Terminal" system in `DESIGN.md` is complete. It builds clean, tests pass, and
the composed screens (menu, Settings, onboarding) were walked by hand on a
real macOS build and confirmed — see "Verified" below.

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
- `./scripts/bundle.sh --no-install` builds and signs clean with the Developer
  ID identity, and `Seen.app/Contents/Resources/Fonts/` contains all four
  JetBrainsMono TTFs plus OFL.txt. The bundle launches and runs.
- `swift scripts/FontCheck.swift build/Seen.app` **passes on macOS**: all four
  faces register, the name "JetBrains Mono" resolves to JetBrains Mono with no
  fallback, each weight maps to a distinct real face (Regular/Medium/SemiBold/
  Bold, not one face synthesised four ways), and i/W/0/l all advance 60.0pt at
  100pt — exactly 0.6em. Re-run it after any change to the font pipeline.

**Verified visually — the design system**

`scripts/DesignProof.swift` was rendered on macOS (1960x2658 @2x) and the image
inspected. Confirmed against `DESIGN.md`:

- Type is genuinely JetBrains Mono — the dotted zero and slab-serifed `l` are
  visible — across all six named steps, each clearly distinct.
- Near-black ground throughout. Every corner square; no rounded shape, no
  capsule, no shadow, nothing rendering in light mode.
- 1px borders read clearly against the ground and carry the hierarchy, with the
  tonal ladder (base / sunken / elevated / raised / high) legible as depth.
- Amber `#FFB46E` reads as the primary action colour: the filled button with
  near-black `#4B2800` text, the selected segmented cell, the accented menu row,
  the app mark. The secondary button is a 1px border with no fill, as specified.
- The code block renders green `$` and blue path on the sunken ground; the
  `> ` marker replaces the icon bullet; status tags are sharp tinted boxes.

**Known behaviour: ligatures are on.** JetBrains Mono ships programming
ligatures and they are enabled by default, which suits the spec's stated "IDE
aesthetic" but means `CommandLineText` renders a path containing `->`, `!=`, or
`<=` as a ligature glyph rather than the literal characters. Left as-is
deliberately; if literal fidelity matters more than the IDE look for that one
component, build its font from an `NSFontDescriptor` with common ligatures
disabled rather than turning them off system-wide.

**Verified: the composed screens**

A human click-through against a real `./scripts/bundle.sh --no-install` build
confirmed `MenuContent`, `SettingsView`, and `OnboardingView` render correctly
in the restyled system — no clipping in the tight spots (onboarding two-button
row, Hotkey pane's key-chip row, Permissions row's trailing tag + button
column), AppKit-drawn surfaces (folder picker, Capture App submenu) honour the
pinned dark appearance, and motion (Hotkey pane's block cursor, menu-bar status
square pulse) behaves as designed.

One follow-up landed from the click-through: the save-directory row in
Settings → General used `CommandLineText` (a green `$` prompt and blue path in
`SeenType.code` at 14px), which is styled for terminal/code output per
`DESIGN.md`, not a plain path readout. Replaced with an unprefixed path in
`SeenTheme.Term.dim` at 12px, same monospace/bordered/sunken-background
treatment.

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
