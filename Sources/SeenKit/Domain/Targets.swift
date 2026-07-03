import CoreGraphics
import Foundation

// Domain is framework-free with one documented exception: CGImage (CoreGraphics)
// is the currency type for in-flight pixel data. Wrapping it would add copies
// and no abstraction value — every capture/OCR/encoding API on the platform
// speaks CGImage.

/// A connected display, as reported by the capture engine.
public struct DisplayInfo: Sendable, Codable, Equatable, Identifiable {
    /// CoreGraphics display ID.
    public var id: UInt32
    /// Pixel dimensions.
    public var width: Int
    public var height: Int
    public var name: String

    public init(id: UInt32, width: Int, height: Int, name: String) {
        self.id = id
        self.width = width
        self.height = height
        self.name = name
    }
}

/// An on-screen window that can be targeted for capture.
public struct AppWindowInfo: Sendable, Codable, Equatable, Identifiable {
    /// CGWindowID.
    public var id: UInt32
    public var appName: String
    public var bundleID: String?
    public var title: String?

    public init(id: UInt32, appName: String, bundleID: String?, title: String?) {
        self.id = id
        self.appName = appName
        self.bundleID = bundleID
        self.title = title
    }
}

/// One raw captured image plus where it came from, before encoding/storage.
/// `@unchecked` because CGImage is immutable and therefore safe to share.
public struct CapturedFrame: @unchecked Sendable {
    public let image: CGImage
    /// Origin label used in filenames and results, e.g. `"display-1"`,
    /// `"google-chrome"`. Will be sanitized by `CaptureFileNaming`.
    public let sourceLabel: String

    public init(image: CGImage, sourceLabel: String) {
        self.image = image
        self.sourceLabel = sourceLabel
    }
}
