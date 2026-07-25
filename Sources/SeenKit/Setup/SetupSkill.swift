import Foundation
#if os(macOS)
import Darwin
#endif

public struct SetupSkill {
    public enum ResolutionError: Error, LocalizedError {
        case skillNotFound(String, String)
        
        public var errorDescription: String? {
            switch self {
            case .skillNotFound(let bundlePath, let devPath):
                return "Could not find SKILL.md in bundle (\(bundlePath)) or repo (\(devPath))"
            }
        }
    }
    
    public static func resolveSourcePath(executableURL: URL) throws -> URL {
        let resolvedURL = executableURL.resolvingSymlinksInPath()
        let resolvedDir = resolvedURL.deletingLastPathComponent()
        
        // 1. Bundle path: ../seen-skill/SKILL.md from bin
        let bundlePath = resolvedDir.deletingLastPathComponent().appendingPathComponent("seen-skill/SKILL.md")
        if FileManager.default.fileExists(atPath: bundlePath.path) {
            return bundlePath
        }
        
        // 2. Dev path: walk up looking for .claude/skills/seen/SKILL.md
        var current = resolvedDir
        let rootPath = URL(fileURLWithPath: "/")
        while current != rootPath {
            let devPath = current.appendingPathComponent(".claude/skills/seen/SKILL.md")
            if FileManager.default.fileExists(atPath: devPath.path) {
                return devPath
            }
            current = current.deletingLastPathComponent()
        }
        
        let dummyDev = resolvedDir.appendingPathComponent(".claude/skills/seen/SKILL.md")
        throw ResolutionError.skillNotFound(bundlePath.path, dummyDev.path)
    }
    
    public static func installSkill(sourceURL: URL, destURL: URL) throws -> Bool {
        let fm = FileManager.default
        let dir = destURL.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        
        let sourceData = try Data(contentsOf: sourceURL)
        
        if fm.fileExists(atPath: destURL.path) {
            let destData = try Data(contentsOf: destURL)
            if sourceData == destData {
                return false // byte identical
            }
        }
        
        let tempURL = dir.appendingPathComponent(".\(destURL.lastPathComponent).tmp.\(UUID().uuidString)")
        try sourceData.write(to: tempURL, options: .atomic)
        
        let status = tempURL.withUnsafeFileSystemRepresentation { tempPath in
            destURL.withUnsafeFileSystemRepresentation { destPath in
                rename(tempPath!, destPath!)
            }
        }
        
        if status != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
        }
        
        return true
    }
}
