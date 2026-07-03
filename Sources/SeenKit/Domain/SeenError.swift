import Foundation

/// Every failure SeenKit surfaces. `code` is the stable machine-readable
/// identifier used in API error payloads (see docs/api.md); `message` is the
/// human/agent-readable detail.
public enum SeenError: Error, Sendable, Equatable {
    /// The named permission (e.g. "screen-recording") hasn't been granted.
    case permissionRequired(String)
    case targetNotFound(String)
    case badRequest(String)
    case sessionLimitExceeded(String)
    case sessionNotFound(UUID)
    case unsupportedFormat(String)
    case captureFailed(String)
    case encodingFailed(String)
    case storageFailed(String)

    public var code: String {
        switch self {
        case .permissionRequired: "permission_required"
        case .targetNotFound: "target_not_found"
        case .badRequest: "bad_request"
        case .sessionLimitExceeded: "session_limit_exceeded"
        case .sessionNotFound: "session_not_found"
        case .unsupportedFormat: "unsupported_format"
        case .captureFailed: "capture_failed"
        case .encodingFailed: "encoding_failed"
        case .storageFailed: "storage_failed"
        }
    }

    public var message: String {
        switch self {
        case .permissionRequired(let permission):
            "Seen needs the \(permission) permission. Open System Settings → Privacy & Security and enable it for Seen, then retry."
        case .targetNotFound(let detail):
            "Capture target not found: \(detail). Use GET /apps or GET /displays to list valid targets."
        case .badRequest(let detail):
            detail
        case .sessionLimitExceeded(let detail):
            "Session limit exceeded: \(detail)."
        case .sessionNotFound(let id):
            "No active session with id \(id.uuidString)."
        case .unsupportedFormat(let detail):
            "Unsupported image format: \(detail)."
        case .captureFailed(let detail):
            "Capture failed: \(detail)."
        case .encodingFailed(let detail):
            "Image encoding failed: \(detail)."
        case .storageFailed(let detail):
            "Saving the capture failed: \(detail)."
        }
    }
}

extension SeenError: LocalizedError {
    public var errorDescription: String? { message }
}
