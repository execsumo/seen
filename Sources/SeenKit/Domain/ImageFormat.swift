/// Encodings a capture can be saved as. Encoder implementations must throw
/// `SeenError.unsupportedFormat` for formats the OS cannot encode (e.g. WebP
/// on older systems) rather than silently substituting another format.
public enum ImageFormat: String, Sendable, Codable, CaseIterable, Equatable {
    case jpeg
    case png
    case webp

    public var fileExtension: String {
        self == .jpeg ? "jpg" : rawValue
    }

    public var mimeType: String {
        switch self {
        case .jpeg: "image/jpeg"
        case .png: "image/png"
        case .webp: "image/webp"
        }
    }
}
