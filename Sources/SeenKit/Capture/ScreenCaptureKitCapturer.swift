import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// ScreenCaptureKit-backed implementation of `ScreenCapturing`.
///
/// Enumerates on-screen, non-trivially-sized surfaces via `SCShareableContent`
/// and captures one-shot frames via `SCScreenshotManager` (no persistent stream,
/// so idle cost is zero). Captures are taken at native pixel resolution.
public final class ScreenCaptureKitCapturer: ScreenCapturing {

    /// Minimum on-screen window dimension (in points) worth capturing or listing.
    private static let minimumWindowDimension: CGFloat = 50

    /// `SCStreamErrorUserDeclined` — the user has not granted Screen Recording.
    private static let screenRecordingDeniedCode: Int = -3801

    /// Creates a capturer over the system's default ScreenCaptureKit session.
    public init() {}

    // MARK: - ScreenCapturing

    /// The connected displays, as reported by `SCShareableContent`.
    public func displays() async throws -> [DisplayInfo] {
        try requireScreenRecordingPermission()
        let content = try await shareableContent()
        return content.displays.map { display in
            DisplayInfo(
                id: display.displayID,
                width: display.width,
                height: display.height,
                name: displayName(for: display)
            )
        }
    }

    /// On-screen, non-trivially-sized windows (≥50×50 pt) grouped by owning
    /// application, each carrying its app name, bundle ID, and optional title.
    public func applications() async throws -> [AppWindowInfo] {
        try requireScreenRecordingPermission()
        let content = try await shareableContent()
        return content.windows
            .filter(isCapturableWindow)
            .compactMap { window -> AppWindowInfo? in
                guard let app = window.owningApplication else { return nil }
                return AppWindowInfo(
                    id: window.windowID,
                    appName: app.applicationName,
                    bundleID: app.bundleIdentifier,
                    title: window.title
                )
            }
    }

    /// Resolves `target` and returns one full-resolution frame per captured
    /// surface. Throws `permissionRequired` without Screen Recording access and
    /// `targetNotFound` when the target doesn't resolve.
    public func capture(_ target: CaptureRequest.Target) async throws -> [CapturedFrame] {
        try requireScreenRecordingPermission()
        let content = try await shareableContent()

        switch target {
        case .allDisplays:
            var frames: [CapturedFrame] = []
            for display in content.displays {
                frames.append(try await captureDisplay(display))
            }
            return frames

        case .display(let id):
            guard let display = content.displays.first(where: { $0.displayID == id }) else {
                throw SeenError.targetNotFound("display \(id)")
            }
            return [try await captureDisplay(display)]

        case .app(let name):
            let matches = content.windows.filter { isCapturableWindow($0) && matchesApp($0, name) }
            guard !matches.isEmpty else {
                throw SeenError.targetNotFound(name)
            }
            var frames: [CapturedFrame] = []
            for window in matches {
                let label = window.owningApplication?.applicationName ?? name
                frames.append(try await captureWindow(window, label: label))
            }
            return frames

        case .window(let id):
            guard let window = content.windows.first(where: { $0.windowID == id && $0.isOnScreen }) else {
                throw SeenError.targetNotFound("window \(id)")
            }
            let label = window.owningApplication?.applicationName ?? "window-\(id)"
            return [try await captureWindow(window, label: label)]
        }
    }

    /// True when Screen Recording access is already granted. Never prompts.
    public func hasScreenRecordingPermission() async -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    // MARK: - Capture helpers

    /// Captures an entire display at native pixel resolution, labelled
    /// `display-<displayID>` (e.g. `display-1` for the built-in display).
    private func captureDisplay(_ display: SCDisplay) async throws -> CapturedFrame {
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let image = try await captureImage(
            filter: filter,
            pointSize: CGSize(width: display.width, height: display.height)
        )
        return CapturedFrame(image: image, sourceLabel: "display-\(display.displayID)")
    }

    /// Captures a single independent window at native pixel resolution. The label
    /// is the owning application's name (sanitized later by `CaptureFileNaming`).
    private func captureWindow(_ window: SCWindow, label: String) async throws -> CapturedFrame {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let image = try await captureImage(filter: filter, pointSize: window.frame.size)
        return CapturedFrame(image: image, sourceLabel: label)
    }

    /// One-shot screenshot of `filter`, sized to its native pixel dimensions.
    private func captureImage(filter: SCContentFilter, pointSize: CGSize) async throws -> CGImage {
        let configuration = SCStreamConfiguration()
        let scale = max(CGFloat(filter.pointPixelScale), 1.0)
        configuration.width = max(1, Int((pointSize.width * scale).rounded()))
        configuration.height = max(1, Int((pointSize.height * scale).rounded()))
        configuration.captureResolution = .best
        configuration.showsCursor = false

        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            // Map SCK's authorization error to a structured `permission_required`;
            // everything else is a generic capture failure.
            if isPermissionError(error) {
                throw SeenError.permissionRequired("screen-recording")
            }
            throw SeenError.captureFailed(error.localizedDescription)
        }
    }

    // MARK: - Enumeration helpers

    private func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.current
    }

    /// Throws `permissionRequired` without prompting when Screen Recording has
    /// not been granted. `CGPreflightScreenCaptureAccess` never triggers a TCC
    /// prompt, so this is safe to call in any context.
    private func requireScreenRecordingPermission() throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw SeenError.permissionRequired("screen-recording")
        }
    }

    /// On-screen windows at least 50×50 points in size.
    private func isCapturableWindow(_ window: SCWindow) -> Bool {
        guard window.isOnScreen else { return false }
        let size = window.frame.size
        return size.width >= Self.minimumWindowDimension
            && size.height >= Self.minimumWindowDimension
    }

    /// Case-insensitive substring match on the owning app's name or bundle ID.
    private func matchesApp(_ window: SCWindow, _ name: String) -> Bool {
        guard let app = window.owningApplication else { return false }
        let query = name.lowercased()
        if app.applicationName.lowercased().contains(query) { return true }
        if app.bundleIdentifier.lowercased().contains(query) { return true }
        return false
    }

    /// Best-effort human-readable display name via AppKit, falling back to
    /// `Display <id>` when the screen can't be matched (e.g. no AppKit session).
    private func displayName(for display: SCDisplay) -> String {
        let screenNumberKey = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
        for screen in NSScreen.screens {
            if let id = (screen.deviceDescription[screenNumberKey] as? NSNumber)?.uint32Value,
               id == display.displayID {
                return screen.localizedName
            }
        }
        return "Display \(display.displayID)"
    }

    /// True when `error` is ScreenCaptureKit's "user declined authorization" error.
    private func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain && nsError.code == Self.screenRecordingDeniedCode
    }
}
