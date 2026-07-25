import Foundation
import SeenKit

let setupTests: [TestCase] = [
    TestCase("setup cursor: merge preserves siblings") {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("mcp.json")
        defer { try? fm.removeItem(at: url.deletingLastPathComponent()) }
        
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let initialJSON = """
        {
          "mcpServers": {
            "other": { "command": "x" }
          },
          "otherKey": "value"
        }
        """.data(using: .utf8)!
        try initialJSON.write(to: url)
        
        let changed = try SetupCursor.merge(into: url)
        try expectEqual(changed, true)
        
        let data = try Data(contentsOf: url)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        try expectEqual(dict["otherKey"] as? String, "value")
        let servers = dict["mcpServers"] as! [String: Any]
        try expectEqual((servers["other"] as! [String: Any])["command"] as? String, "x")
        try expectEqual((servers["seen"] as! [String: Any])["command"] as? String, "seen")
    },
    
    TestCase("setup cursor: merge replaces existing seen key without duplicating and returns true if changed") {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("mcp.json")
        defer { try? fm.removeItem(at: url.deletingLastPathComponent()) }
        
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let initialJSON = """
        {
          "mcpServers": {
            "seen": { "command": "old", "args": [] }
          }
        }
        """.data(using: .utf8)!
        try initialJSON.write(to: url)
        
        let changed = try SetupCursor.merge(into: url)
        try expectEqual(changed, true)
        
        let data = try Data(contentsOf: url)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let servers = dict["mcpServers"] as! [String: Any]
        try expectEqual(servers.count, 1)
        try expectEqual((servers["seen"] as! [String: Any])["command"] as? String, "seen")
        try expectEqual((servers["seen"] as! [String: Any])["args"] as? [String], ["mcp"])
    },
    
    TestCase("setup cursor: merge does nothing if already identical") {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("mcp.json")
        defer { try? fm.removeItem(at: url.deletingLastPathComponent()) }
        
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let initialJSON = """
        {
          "mcpServers": {
            "seen": { "command": "seen", "args": ["mcp"] }
          }
        }
        """.data(using: .utf8)!
        try initialJSON.write(to: url)
        
        let changed = try SetupCursor.merge(into: url)
        try expectEqual(changed, false)
    },
    
    TestCase("setup cursor: malformed input throws") {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("mcp.json")
        defer { try? fm.removeItem(at: url.deletingLastPathComponent()) }
        
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not json".data(using: .utf8)!.write(to: url)
        
        _ = try await expectThrows { _ = try SetupCursor.merge(into: url) }
        
        // Ensure not replaced
        let data = try Data(contentsOf: url)
        try expectEqual(String(data: data, encoding: .utf8), "not json")
    },
    
    TestCase("setup cursor: atomic write leaves no temp file behind") {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("mcp.json")
        defer { try? fm.removeItem(at: dir) }
        
        _ = try SetupCursor.merge(into: url)
        
        let contents = try fm.contentsOfDirectory(atPath: dir.path)
        try expectEqual(contents.count, 1)
        try expectEqual(contents[0], "mcp.json")
    },
    
    TestCase("setup skill: resolution picks bundle path when present") {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: dir) }
        
        let exeDir = dir.appendingPathComponent("Seen.app/Contents/Resources/bin")
        try fm.createDirectory(at: exeDir, withIntermediateDirectories: true)
        let exeURL = exeDir.appendingPathComponent("seen")
        
        let bundleSkillDir = dir.appendingPathComponent("Seen.app/Contents/Resources/seen-skill")
        try fm.createDirectory(at: bundleSkillDir, withIntermediateDirectories: true)
        let bundleSkillURL = bundleSkillDir.appendingPathComponent("SKILL.md")
        try "bundle".data(using: .utf8)!.write(to: bundleSkillURL)
        
        let resolved = try SetupSkill.resolveSourcePath(executableURL: exeURL)
        try expectEqual(resolved.path, bundleSkillURL.path)
    },
    
    TestCase("setup skill: resolution picks repo path otherwise") {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: dir) }
        
        let buildDir = dir.appendingPathComponent(".build/debug")
        try fm.createDirectory(at: buildDir, withIntermediateDirectories: true)
        let exeURL = buildDir.appendingPathComponent("seen")
        
        let repoSkillDir = dir.appendingPathComponent(".claude/skills/seen")
        try fm.createDirectory(at: repoSkillDir, withIntermediateDirectories: true)
        let repoSkillURL = repoSkillDir.appendingPathComponent("SKILL.md")
        try "repo".data(using: .utf8)!.write(to: repoSkillURL)
        
        let resolved = try SetupSkill.resolveSourcePath(executableURL: exeURL)
        try expectEqual(resolved.path, repoSkillURL.path)
    },
    
    TestCase("setup skill: resolution throws if neither found") {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: dir) }
        
        let buildDir = dir.appendingPathComponent(".build/debug")
        try fm.createDirectory(at: buildDir, withIntermediateDirectories: true)
        let exeURL = buildDir.appendingPathComponent("seen")
        
        _ = try await expectThrows { _ = try SetupSkill.resolveSourcePath(executableURL: exeURL) }
    },
    
    TestCase("setup skill: resolution resolves symlinks before searching") {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: dir) }
        
        // Setup actual binary location
        let realDir = dir.appendingPathComponent("real/Seen.app/Contents/Resources/bin")
        try fm.createDirectory(at: realDir, withIntermediateDirectories: true)
        let realExeURL = realDir.appendingPathComponent("seen")
        try "dummy".data(using: .utf8)!.write(to: realExeURL)
        
        // Setup SKILL.md relative to real location
        let bundleSkillDir = dir.appendingPathComponent("real/Seen.app/Contents/Resources/seen-skill")
        try fm.createDirectory(at: bundleSkillDir, withIntermediateDirectories: true)
        let bundleSkillURL = bundleSkillDir.appendingPathComponent("SKILL.md")
        try "bundle".data(using: .utf8)!.write(to: bundleSkillURL)
        
        // Create symlink
        let symlinkDir = dir.appendingPathComponent("symlink")
        try fm.createDirectory(at: symlinkDir, withIntermediateDirectories: true)
        let symlinkURL = symlinkDir.appendingPathComponent("seen")
        try fm.createSymbolicLink(at: symlinkURL, withDestinationURL: realExeURL)
        
        // Test resolution using symlink
        let resolved = try SetupSkill.resolveSourcePath(executableURL: symlinkURL)
        try expectEqual(resolved.path, bundleSkillURL.path)
    }
]
