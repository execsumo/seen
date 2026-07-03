# Workstream A — Core Capture Engine

## 1. OBJECTIVE

Implement SeenKit's capture engine: ScreenCaptureKit capturer, Vision OCR,
ImageIO encoder, directory storage, and the `CaptureCoordinator` that
orchestrates them — fully tested via `swift run SeenTests`.

## 2. CONTEXT

- You are in an isolated git worktree of `~/projects/seen` on branch
  `delegate/cline-core`. Work only here.
- **Read first:** `ARCHITECTURE.md`, `docs/api.md`, and everything in
  `Sources/SeenKit/Domain/` — Domain is the **frozen contract**. You implement
  its protocols; you may NOT edit Domain files or `Package.swift`. If a Domain
  type blocks you, escalate (see §4) — do not work around it.
- Toolchain: Swift 6.3 via Command Line Tools only. **No Xcode, no XCTest, no
  `swift test`, no xcodebuild.** Build with `swift build`; run tests with
  `swift run SeenTests` (an executable runner — see `Sources/SeenTests/TestKit.swift`).
- Target macOS 15+. Swift 6 strict concurrency is on; use actors for mutable state.
- This machine has other delegates working on Server/Sessions/CLI (workstream B)
  and the app shell (workstream C) in parallel. Your write scope (only these):
  - `Sources/SeenKit/Capture/` `OCR/` `Imaging/` `Storage/` `Coordinator/`
  - `Sources/SeenTests/CoreEngineTests.swift`
  - one line in `Sources/SeenTests/AllTests.swift` registering `coreEngineTests`

### What to build

1. **`Capture/ScreenCaptureKitCapturer.swift`** — implements `ScreenCapturing`.
   - `displays()` / `applications()` via `SCShareableContent`. Windows: on
     screen, non-trivial size (skip < 50×50 px), with owning app name/bundle ID.
   - `capture(_:)` via `SCScreenshotManager.captureImage` (one-shot; never hold
     a stream). `.allDisplays` → one frame per display (label `display-<n>`);
     `.display(id)` → that display; `.app(name)` → case-insensitive substring
     match on app name or bundle ID, capture each matching on-screen window
     (label = sanitizable app name); `.window(id)` → that window. Capture at
     native pixel resolution.
   - No match → throw `SeenError.targetNotFound` with the queried name.
   - Missing permission → throw `SeenError.permissionRequired("screen-recording")`
     (map SCK's authorization errors). `hasScreenRecordingPermission()` via
     `CGPreflightScreenCaptureAccess()`.
2. **`OCR/VisionTextRecognizer.swift`** — implements `TextRecognizing` with
   `VNRecognizeTextRequest` (`.accurate`, language correction on). Join
   observations in natural reading order (top-to-bottom, left-to-right).
   Return `nil` when nothing is recognized.
3. **`Imaging/ImageIOEncoder.swift`** — implements `ImageEncoding`.
   - Downscale longest edge to `options.maxDimension` (aspect preserved, never
     upscale) via CoreGraphics, then encode via `CGImageDestination`.
   - Formats: jpeg/png/heic always; webp only if
     `CGImageDestinationCopyTypeIdentifiers()` includes it, else throw
     `SeenError.unsupportedFormat`.
4. **`Storage/DirectoryCaptureStore.swift`** — implements `CaptureStoring`.
   - `init(configurationProvider: @escaping @Sendable () -> CaptureConfiguration)`;
     reads `saveDirectoryPath` per call (settings change live). Creates the
     directory as needed. Names files with `CaptureFileNaming.filename`. On
     collision append `-2`, `-3`, … before the extension.
5. **`Coordinator/CaptureCoordinator.swift`** — `public actor CaptureCoordinator:
   CaptureCoordinating` with exactly this init (integration depends on it):
   ```swift
   public init(
       capturer: any ScreenCapturing,
       recognizer: any TextRecognizing,
       encoder: any ImageEncoding,
       store: any CaptureStoring,
       configurationProvider: @escaping @Sendable () -> CaptureConfiguration
   )
   ```
   - `perform(_:)`: capture frames → if `request.output.includesText`, OCR the
     **full-resolution** CGImage → encode with
     `configurationProvider().encodingOptions(for: request)` → store → assemble
     `CaptureResult` (`text: nil` when OCR not requested, `""` when OCR found
     nothing). Emit `.captureCompleted` on success / `.captureFailed` on error
     (then rethrow).
   - `observeEvents(_:)` appends handlers; also expose
     `public func emit(_ event: CaptureEvent)` so the session manager
     (workstream B) can fan its events through the same observers at integration.

### Tests (`coreEngineTests`)

Mock every protocol; generate synthetic `CGImage`s in memory (e.g. solid-color
bitmap contexts; for the OCR test, render a short string with CoreText).
Must cover at least:
- Coordinator: all three `output` modes produce correct `text` semantics; OCR
  receives the full-res image while the stored image is downscaled; failure
  emits `.captureFailed`; events reach multiple observers.
- Encoder: downscale math (longest edge, aspect ratio, no upscaling), jpeg and
  png round-trip dimensions, webp behavior (encode OR clean
  `unsupportedFormat` — assert dynamically on what the OS reports).
- Store: filename convention, directory auto-creation (use a temp dir), and
  collision suffixing.
- OCR: recognizes rendered text (assert case-insensitive containment);
  returns nil-or-found semantics on a blank image.

**Tests must pass without Screen Recording permission** — never call
ScreenCaptureKit from tests.

## 3. DEFINITION OF DONE

All of the following, run from your worktree root, must succeed (I will run
these exact commands myself):

1. `swift build` exits 0 with no warnings introduced by your files.
2. `swift run SeenTests` exits 0, and its output lists your new
   `coreEngineTests` cases.
3. `git status --porcelain` is clean (everything committed) and
   `git diff main --stat` touches only your allowed paths (§2).
4. Every public type/method you add has a doc comment; code reads like the
   existing Domain code.

## 4. ESCALATION — stop and ask instead of guessing when:

- A Domain type/protocol doesn't fit what you need (never edit Domain).
- The same failure persists after 2–3 attempts, or SCK/Vision APIs behave
  differently than specced.
- Anything requires the Screen Recording permission, a GUI, network access, or
  touching files outside your scope.
- The real fix is meaningfully bigger than this spec implies.

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

Commit your work to your branch in small, descriptive commits. When the
Definition of Done is green, run `./.delegate/notify done "<one-paragraph
summary>"` and wait at your prompt.

## 7. SCOPE BOUNDARY

Stay inside your worktree. Do not push, open PRs, install anything to
/Applications, launch GUI apps, trigger permission prompts, or run
irreversible/outward-facing commands. Do not modify `Sources/SeenKit/Domain/`,
`Package.swift`, `Sources/SeenApp/`, `Sources/seen-cli/`, or another
workstream's directories.
