import Foundation

/// A request to capture the screen, from any origin (HTTP API, MCP, CLI, hotkey, menu).
public struct CaptureRequest: Sendable, Equatable {
    /// What to capture. Defaults to every connected display.
    public enum Target: Sendable, Equatable {
        /// One image per connected display (the default).
        case allDisplays
        /// A single display by its CoreGraphics display ID.
        case display(UInt32)
        /// All on-screen windows of the app whose name (or bundle ID) fuzzy-matches.
        case app(String)
        /// A single window by its CGWindowID.
        case window(UInt32)
    }

    /// What the caller wants back. The image file is always saved regardless
    /// (product requirement: every capture lands in the save directory).
    public enum Output: String, Sendable, Codable, CaseIterable {
        case image, text, both

        public var includesImage: Bool { self != .text }
        public var includesText: Bool { self != .image }
    }

    public var target: Target
    public var output: Output
    /// Overrides for the configured defaults; `nil` means "use settings".
    public var format: ImageFormat?
    public var quality: Double?
    public var maxDimension: Int?

    public init(
        target: Target = .allDisplays,
        output: Output = .both,
        format: ImageFormat? = nil,
        quality: Double? = nil,
        maxDimension: Int? = nil
    ) {
        self.target = target
        self.output = output
        self.format = format
        self.quality = quality
        self.maxDimension = maxDimension
    }
}

// MARK: - Codable

// JSON shape (see docs/api.md):
//   {"target": "all" | {"display": 1} | {"app": "Chrome"} | {"window": 123},
//    "output": "image" | "text" | "both",
//    "format": "jpeg", "quality": 0.75, "maxDimension": 1568}
// Every field is optional; omitted fields fall back to defaults.

extension CaptureRequest: Codable {
    private enum CodingKeys: String, CodingKey {
        case target, output, format, quality, maxDimension
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decodeIfPresent(Target.self, forKey: .target) ?? .allDisplays
        output = try container.decodeIfPresent(Output.self, forKey: .output) ?? .both
        format = try container.decodeIfPresent(ImageFormat.self, forKey: .format)
        quality = try container.decodeIfPresent(Double.self, forKey: .quality)
        maxDimension = try container.decodeIfPresent(Int.self, forKey: .maxDimension)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(output, forKey: .output)
        try container.encodeIfPresent(format, forKey: .format)
        try container.encodeIfPresent(quality, forKey: .quality)
        try container.encodeIfPresent(maxDimension, forKey: .maxDimension)
    }
}

extension CaptureRequest.Target: Codable {
    private enum CodingKeys: String, CodingKey {
        case display, app, window
    }

    public init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let raw = try? single.decode(String.self) {
            guard raw == "all" else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown target \"\(raw)\"; expected \"all\" or an object."
                ))
            }
            self = .allDisplays
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try container.decodeIfPresent(UInt32.self, forKey: .display) {
            self = .display(id)
        } else if let name = try container.decodeIfPresent(String.self, forKey: .app) {
            self = .app(name)
        } else if let id = try container.decodeIfPresent(UInt32.self, forKey: .window) {
            self = .window(id)
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: #"Target must be "all", {"display":id}, {"app":"name"}, or {"window":id}."#
            ))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .allDisplays:
            var container = encoder.singleValueContainer()
            try container.encode("all")
        case .display(let id):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .display)
        case .app(let name):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .app)
        case .window(let id):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .window)
        }
    }
}
