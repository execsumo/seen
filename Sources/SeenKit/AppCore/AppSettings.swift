import Foundation
import Observation

@MainActor
@Observable
public final class AppSettings {
    public var saveDirectoryPath: String {
        didSet { defaults.set(saveDirectoryPath, forKey: "saveDirectoryPath") }
    }
    // Image encoding is built into the app, not user-configurable: PNG at 1568 px
    // is the right default for every capture — lossless, so on-screen text stays
    // artifact-free for the vision model, at no extra token cost (Claude bills
    // images by dimensions, not bytes). OCR also runs on the full-resolution frame
    // first, so the downscale never costs text fidelity. Agents that want a smaller
    // payload override format/quality/size per request via the API. Kept as the
    // per-request fallback in `configurationProvider`; never persisted, so no stale
    // value can resurrect.
    public let defaultFormat: ImageFormat
    public let defaultQuality: Double
    public let defaultMaxDimension: Int
    
    public var hotkeyCode: Int {
        didSet { defaults.set(hotkeyCode, forKey: "hotkeyCode") }
    }
    public var hotkeyModifiers: Int {
        didSet { defaults.set(hotkeyModifiers, forKey: "hotkeyModifiers") }
    }
    
    public var captureOutput: CaptureRequest.Output {
        didSet {
            let str: String
            switch captureOutput {
            case .image: str = "image"
            case .text: str = "text"
            case .both: str = "both"
            }
            defaults.set(str, forKey: "captureOutput")
        }
    }
    
    private let defaults: UserDefaults
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        let initialConfig = CaptureConfiguration()
        self.saveDirectoryPath = defaults.string(forKey: "saveDirectoryPath") ?? initialConfig.saveDirectoryPath

        // Always the built-in encoding defaults — deliberately not read from
        // UserDefaults, so a value an older build's UI persisted can't stick.
        self.defaultFormat = initialConfig.defaultFormat
        self.defaultQuality = initialConfig.defaultQuality
        self.defaultMaxDimension = initialConfig.defaultMaxDimension

        if defaults.object(forKey: "hotkeyCode") != nil {
            self.hotkeyCode = defaults.integer(forKey: "hotkeyCode")
        } else {
            self.hotkeyCode = 1 // S
        }
        
        if defaults.object(forKey: "hotkeyModifiers") != nil {
            self.hotkeyModifiers = defaults.integer(forKey: "hotkeyModifiers")
        } else {
            // Carbon modifier flags (what RegisterEventHotKey consumes):
            // controlKey(0x1000) | optionKey(0x800) | cmdKey(0x100) = ⌃⌥⌘.
            self.hotkeyModifiers = 0x1000 | 0x800 | 0x100 // 6400
        }
        
        if let outStr = defaults.string(forKey: "captureOutput") {
            switch outStr {
            case "image": self.captureOutput = .image
            case "text": self.captureOutput = .text
            default: self.captureOutput = .both
            }
        } else {
            self.captureOutput = .both
        }
    }
    
    public var captureConfiguration: CaptureConfiguration {
        CaptureConfiguration(
            saveDirectoryPath: saveDirectoryPath,
            defaultFormat: defaultFormat,
            defaultQuality: defaultQuality,
            defaultMaxDimension: defaultMaxDimension
        )
    }
    
    public var configurationProvider: @Sendable () -> CaptureConfiguration {
        let savePath = self.saveDirectoryPath
        let format = self.defaultFormat
        let quality = self.defaultQuality
        let maxDim = self.defaultMaxDimension
        return {
            CaptureConfiguration(
                saveDirectoryPath: savePath,
                defaultFormat: format,
                defaultQuality: quality,
                defaultMaxDimension: maxDim
            )
        }
    }
}
