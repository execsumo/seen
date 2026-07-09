import Foundation
import Observation

@MainActor
@Observable
public final class AppSettings {
    public var saveDirectoryPath: String {
        didSet { defaults.set(saveDirectoryPath, forKey: "saveDirectoryPath") }
    }
    public var defaultFormat: ImageFormat {
        didSet { defaults.set(defaultFormat.rawValue, forKey: "defaultFormat") }
    }
    public var defaultQuality: Double {
        didSet { defaults.set(defaultQuality, forKey: "defaultQuality") }
    }
    public var defaultMaxDimension: Int {
        didSet { defaults.set(defaultMaxDimension, forKey: "defaultMaxDimension") }
    }
    
    public var hotkeyCode: Int {
        didSet { defaults.set(hotkeyCode, forKey: "hotkeyCode") }
    }
    public var hotkeyModifiers: Int {
        didSet { defaults.set(hotkeyModifiers, forKey: "hotkeyModifiers") }
    }
    
    public var pushDestination: PushDestination {
        didSet {
            if let data = try? JSONEncoder().encode(pushDestination) {
                defaults.set(data, forKey: "pushDestination")
            }
        }
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
        
        if let formatRaw = defaults.string(forKey: "defaultFormat"), let format = ImageFormat(rawValue: formatRaw) {
            self.defaultFormat = format
        } else {
            self.defaultFormat = initialConfig.defaultFormat
        }
        
        if defaults.object(forKey: "defaultQuality") != nil {
            self.defaultQuality = defaults.double(forKey: "defaultQuality")
        } else {
            self.defaultQuality = initialConfig.defaultQuality
        }
        
        if defaults.object(forKey: "defaultMaxDimension") != nil {
            self.defaultMaxDimension = defaults.integer(forKey: "defaultMaxDimension")
        } else {
            self.defaultMaxDimension = initialConfig.defaultMaxDimension
        }
        
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
        
        if let data = defaults.data(forKey: "pushDestination"),
           let dest = try? JSONDecoder().decode(PushDestination.self, from: data) {
            self.pushDestination = dest
        } else {
            // Clipboard by default: it spawns nothing under Seen, so the hotkey
            // never drags a child process's TCC prompts onto the app. Users can
            // switch to a command template or tmux in Settings → Destination.
            self.pushDestination = .clipboard
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
