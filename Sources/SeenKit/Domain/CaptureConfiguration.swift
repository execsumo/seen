import Foundation

/// User-configurable capture defaults, owned by Settings and injected into the
/// coordinator as a provider closure so changes apply without restarts.
/// Per-request overrides in `CaptureRequest` take precedence over these.
public struct CaptureConfiguration: Sendable, Codable, Equatable {
    public var saveDirectoryPath: String
    public var defaultFormat: ImageFormat
    public var defaultQuality: Double
    /// Longest-edge cap in pixels for saved images. 1568 px is the Anthropic
    /// vision sweet spot; larger images are downscaled server-side anyway and
    /// only cost extra tokens.
    public var defaultMaxDimension: Int

    public init(
        saveDirectoryPath: String = SeenPaths.defaultSaveDirectory.path,
        defaultFormat: ImageFormat = .png,
        defaultQuality: Double = 0.75,
        defaultMaxDimension: Int = 1568
    ) {
        self.saveDirectoryPath = saveDirectoryPath
        self.defaultFormat = defaultFormat
        self.defaultQuality = defaultQuality
        self.defaultMaxDimension = defaultMaxDimension
    }

    /// The effective encoding options for a request, after applying overrides.
    public func encodingOptions(for request: CaptureRequest) -> EncodingOptions {
        EncodingOptions(
            format: request.format ?? defaultFormat,
            quality: request.quality ?? defaultQuality,
            maxDimension: request.maxDimension ?? defaultMaxDimension
        )
    }
}
