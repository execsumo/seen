import Foundation
#if os(macOS)
import Darwin
#endif

public enum SetupError: Error, LocalizedError {
    case malformedJSON(URL)
    case notJSONDictionary(URL)
    
    public var errorDescription: String? {
        switch self {
        case .malformedJSON(let url):
            return "File exists but is not valid JSON: \(url.path)"
        case .notJSONDictionary(let url):
            return "File exists but is not a JSON dictionary: \(url.path)"
        }
    }
}

public struct SetupCursor {
    public static func merge(into configPath: URL) throws -> Bool {
        let fm = FileManager.default
        let dir = configPath.deletingLastPathComponent()
        
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        
        var jsonDict: [String: Any] = [:]
        
        if fm.fileExists(atPath: configPath.path) {
            let data = try Data(contentsOf: configPath)
            if !data.isEmpty {
                do {
                    let parsed = try JSONSerialization.jsonObject(with: data, options: [])
                    guard let dict = parsed as? [String: Any] else {
                        throw SetupError.notJSONDictionary(configPath)
                    }
                    jsonDict = dict
                } catch {
                    if error is SetupError { throw error }
                    throw SetupError.malformedJSON(configPath)
                }
            }
        }
        
        var mcpServers = jsonDict["mcpServers"] as? [String: Any] ?? [:]
        
        let targetSeenConfig: [String: Any] = [
            "command": "seen",
            "args": ["mcp"]
        ]
        
        if let existingSeen = mcpServers["seen"] as? [String: Any],
           let existingCommand = existingSeen["command"] as? String,
           let existingArgs = existingSeen["args"] as? [String],
           existingCommand == "seen" && existingArgs == ["mcp"] {
            // No change needed
            return false
        }
        
        mcpServers["seen"] = targetSeenConfig
        jsonDict["mcpServers"] = mcpServers
        
        let outputData = try JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        
        let tempURL = dir.appendingPathComponent(".\(configPath.lastPathComponent).tmp.\(UUID().uuidString)")
        try outputData.write(to: tempURL, options: .atomic)
        
        let status = tempURL.withUnsafeFileSystemRepresentation { tempPath in
            configPath.withUnsafeFileSystemRepresentation { destPath in
                rename(tempPath!, destPath!)
            }
        }
        
        if status != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
        }
        
        return true
    }
}
