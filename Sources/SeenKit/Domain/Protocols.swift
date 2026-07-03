import CoreGraphics
import Foundation

// The service seams of SeenKit. Implementations live in sibling directories
// (Capture/, OCR/, Imaging/, Storage/, Coordinator/); everything downstream
// (Server/, Push/, SeenApp) depends only on these protocols so each layer is
// independently buildable and testable with mocks.

// MARK: - Capture

public protocol ScreenCapturing: Sendable {
    func displays() async throws -> [DisplayInfo]
    /// On-screen, non-trivially-sized windows grouped by owning application.
    func applications() async throws -> [AppWindowInfo]
    /// Resolves the target and returns one frame per captured surface.
    /// Throws `SeenError.permissionRequired` without Screen Recording access
    /// and `SeenError.targetNotFound` when the target doesn't resolve.
    func capture(_ target: CaptureRequest.Target) async throws -> [CapturedFrame]
    func hasScreenRecordingPermission() async -> Bool
}

// MARK: - OCR

public protocol TextRecognizing: Sendable {
    /// Recognized text in natural reading order, or `nil` when the image
    /// contains no recognizable text. Runs on the full-resolution image
    /// (callers OCR *before* downscaling).
    func recognizeText(in image: CGImage) async throws -> String?
}

// MARK: - Encoding

public struct EncodingOptions: Sendable, Equatable {
    public var format: ImageFormat
    /// 0...1; ignored by lossless formats.
    public var quality: Double
    /// Longest-edge cap in pixels; `nil` = keep original size.
    public var maxDimension: Int?

    public init(format: ImageFormat, quality: Double, maxDimension: Int?) {
        self.format = format
        self.quality = quality
        self.maxDimension = maxDimension
    }
}

public struct EncodedImage: Sendable {
    public var data: Data
    public var format: ImageFormat
    /// Dimensions after any downscaling.
    public var width: Int
    public var height: Int

    public init(data: Data, format: ImageFormat, width: Int, height: Int) {
        self.data = data
        self.format = format
        self.width = width
        self.height = height
    }
}

public protocol ImageEncoding: Sendable {
    /// Downscales (preserving aspect ratio) and encodes. Throws
    /// `SeenError.unsupportedFormat` when the OS can't encode `options.format`.
    func encode(_ image: CGImage, options: EncodingOptions) throws -> EncodedImage
}

// MARK: - Storage

public protocol CaptureStoring: Sendable {
    /// Persists to the configured directory using `CaptureFileNaming`,
    /// creating the directory if needed. Returns the saved file's URL.
    func store(_ image: EncodedImage, sourceLabel: String, timestamp: Date) throws -> URL
}

// MARK: - Coordination

/// Events every capture origin emits; the menu bar icon and API observe these.
public enum CaptureEvent: Sendable {
    case captureCompleted(CaptureResult)
    case captureFailed(String)
    case sessionStarted(SessionInfo)
    case sessionEnded(id: UUID)
}

/// The single entry point for performing captures, regardless of origin.
public protocol CaptureCoordinating: Sendable {
    /// Capture → OCR (full-res, if requested) → encode → store → result.
    func perform(_ request: CaptureRequest) async throws -> CaptureResult
    /// Registers an observer for capture lifecycle events. Handlers may be
    /// called on any thread; hop to the main actor for UI work.
    func observeEvents(_ handler: @escaping @Sendable (CaptureEvent) -> Void) async
}
