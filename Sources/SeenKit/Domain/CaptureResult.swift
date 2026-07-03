import Foundation

/// The outcome of one `CaptureRequest` — one item per captured image
/// (multiple displays or multiple app windows produce multiple items).
public struct CaptureResult: Sendable, Codable, Equatable {
    public struct Item: Sendable, Codable, Equatable {
        /// Absolute path of the saved image file. Captures are always saved.
        public var path: String
        /// Human-readable origin, e.g. `"display-1"` or `"google-chrome"`.
        public var sourceLabel: String
        /// Dimensions of the *saved* (possibly downscaled) image, in pixels.
        public var width: Int
        public var height: Int
        public var byteSize: Int
        /// OCR text. `nil` = OCR was not requested; `""` = OCR ran and found
        /// no text (callers must distinguish the two).
        public var text: String?

        public init(path: String, sourceLabel: String, width: Int, height: Int, byteSize: Int, text: String?) {
            self.path = path
            self.sourceLabel = sourceLabel
            self.width = width
            self.height = height
            self.byteSize = byteSize
            self.text = text
        }
    }

    public var items: [Item]
    public var timestamp: Date

    public init(items: [Item], timestamp: Date) {
        self.items = items
        self.timestamp = timestamp
    }

    /// All OCR text across items, each block prefixed with its source label
    /// when there is more than one item. Empty string if no text anywhere.
    public var combinedText: String {
        let texts = items.compactMap { item -> String? in
            guard let text = item.text, !text.isEmpty else { return nil }
            return items.count > 1 ? "[\(item.sourceLabel)]\n\(text)" : text
        }
        return texts.joined(separator: "\n\n")
    }
}
