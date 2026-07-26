import Foundation
import SeenKit

let setupTests: [TestCase] = [
    TestCase("setup mcp json: merge preserves siblings") {
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
        
        let changed = try SetupMCPJSON.merge(into: url)
        try expectEqual(changed, true)
        
        let data = try Data(contentsOf: url)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        try expectEqual(dict["otherKey"] as? String, "value")
        let servers = dict["mcpServers"] as! [String: Any]
        try expectEqual((servers["other"] as! [String: Any])["command"] as? String, "x")
        try expectEqual((servers["seen"] as! [String: Any])["command"] as? String, "seen")
    },
    
    TestCase("setup mcp json: merge replaces existing seen key without duplicating and returns true if changed") {
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
        
        let changed = try SetupMCPJSON.merge(into: url)
        try expectEqual(changed, true)
        
        let data = try Data(contentsOf: url)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let servers = dict["mcpServers"] as! [String: Any]
        try expectEqual(servers.count, 1)
        try expectEqual((servers["seen"] as! [String: Any])["command"] as? String, "seen")
        try expectEqual((servers["seen"] as! [String: Any])["args"] as? [String], ["mcp"])
    },
    
    TestCase("setup mcp json: merge does nothing if already identical") {
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
        
        let changed = try SetupMCPJSON.merge(into: url)
        try expectEqual(changed, false)
    },
    
    TestCase("setup mcp json: malformed input throws") {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("mcp.json")
        defer { try? fm.removeItem(at: url.deletingLastPathComponent()) }
        
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not json".data(using: .utf8)!.write(to: url)
        
        _ = try await expectThrows { _ = try SetupMCPJSON.merge(into: url) }
        
        // Ensure not replaced
        let data = try Data(contentsOf: url)
        try expectEqual(String(data: data, encoding: .utf8), "not json")
    },
    
    TestCase("setup mcp json: atomic write leaves no temp file behind") {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("mcp.json")
        defer { try? fm.removeItem(at: dir) }
        
        _ = try SetupMCPJSON.merge(into: url)
        
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
    },
    
    TestCase("setup cli: resolveExecutable finds first match") {
        let pathEnv = "/usr/bin:/opt/homebrew/bin:/usr/local/bin"

        let exec = SetupCLI.resolveExecutable(named: "claude", pathEnv: pathEnv) { path in
            return path == "/opt/homebrew/bin/claude"
        }

        try expectEqual(exec, "/opt/homebrew/bin/claude")
    },

    TestCase("setup cli: resolveExecutable honours the requested name") {
        let pathEnv = "/usr/bin:/opt/homebrew/bin"

        let exec = SetupCLI.resolveExecutable(named: "codex", pathEnv: pathEnv) { path in
            return path == "/opt/homebrew/bin/codex"
        }

        try expectEqual(exec, "/opt/homebrew/bin/codex")
        try expectEqual(SetupCLI.resolveExecutable(named: "claude", pathEnv: pathEnv) { path in
            return path == "/opt/homebrew/bin/codex"
        }, String?.none)
    },

    TestCase("setup cli: resolveExecutable returns nil for nil or empty or none executable") {
        try expectEqual(SetupCLI.resolveExecutable(named: "claude", pathEnv: nil, isExecutable: { _ in true }), String?.none)
        try expectEqual(SetupCLI.resolveExecutable(named: "claude", pathEnv: "", isExecutable: { _ in true }), String?.none)
        try expectEqual(SetupCLI.resolveExecutable(named: "claude", pathEnv: "/usr/bin", isExecutable: { _ in false }), String?.none)
    },

    TestCase("harness: claude registers MCP through its CLI with an explicit scope") {
        let home = URL(fileURLWithPath: "/home")
        let ws = URL(fileURLWithPath: "/ws")

        // claude's default scope is `local` (private, cwd-bound), which matches
        // neither of ours — it must always be passed explicitly.
        try expectEqual(
            SetupHarness.claude.mcpInstall(scope: .global, home: home, workspace: ws),
            .cli(executable: "claude", arguments: ["mcp", "add", "seen", "-s", "user", "--", "seen", "mcp"])
        )
        try expectEqual(
            SetupHarness.claude.mcpInstall(scope: .project, home: home, workspace: ws),
            .cli(executable: "claude", arguments: ["mcp", "add", "seen", "-s", "project", "--", "seen", "mcp"])
        )
    },

    TestCase("harness: codex registers MCP through its CLI and is global only") {
        let home = URL(fileURLWithPath: "/home")
        let ws = URL(fileURLWithPath: "/ws")

        try expectEqual(
            SetupHarness.codex.mcpInstall(scope: .global, home: home, workspace: ws),
            .cli(executable: "codex", arguments: ["mcp", "add", "seen", "--", "seen", "mcp"])
        )
        try expectEqual(SetupHarness.codex.supports(.global), true)
        try expectEqual(SetupHarness.codex.supports(.project), false)
    },

    TestCase("harness: cursor and antigravity share the JSON merge, differing only in path") {
        let home = URL(fileURLWithPath: "/home")
        let ws = URL(fileURLWithPath: "/ws")

        try expectEqual(
            SetupHarness.cursor.mcpInstall(scope: .global, home: home, workspace: ws),
            .jsonMerge(URL(fileURLWithPath: "/home/.cursor/mcp.json"))
        )
        try expectEqual(
            SetupHarness.cursor.mcpInstall(scope: .project, home: home, workspace: ws),
            .jsonMerge(URL(fileURLWithPath: "/ws/.cursor/mcp.json"))
        )
        try expectEqual(
            SetupHarness.antigravity.mcpInstall(scope: .global, home: home, workspace: ws),
            .jsonMerge(URL(fileURLWithPath: "/home/.gemini/config/mcp_config.json"))
        )
        try expectEqual(
            SetupHarness.antigravity.mcpInstall(scope: .project, home: home, workspace: ws),
            .jsonMerge(URL(fileURLWithPath: "/ws/.agents/mcp_config.json"))
        )
    },

    TestCase("harness: skill destinations match each harness layout") {
        let home = URL(fileURLWithPath: "/home")
        let ws = URL(fileURLWithPath: "/ws")

        func dest(_ h: SetupHarness, _ s: SetupScope) -> String? {
            h.skillDestination(scope: s, home: home, workspace: ws)?.path
        }

        try expectEqual(dest(.claude, .global), "/home/.claude/skills/seen/SKILL.md")
        try expectEqual(dest(.claude, .project), "/ws/.claude/skills/seen/SKILL.md")
        // Codex skills are $CODEX_HOME/skills/<name>, global regardless of scope.
        try expectEqual(dest(.codex, .global), "/home/.codex/skills/seen/SKILL.md")
        try expectEqual(dest(.antigravity, .global), "/home/.gemini/config/skills/seen/SKILL.md")
        try expectEqual(dest(.antigravity, .project), "/ws/.agents/skills/seen/SKILL.md")
        // Cursor has mcp.json and hooks.json but no skills directory.
        try expectEqual(dest(.cursor, .global), String?.none)
    },

    TestCase("harness: every harness is reachable and names a scope") {
        try expectEqual(SetupHarness.allCases.count, 4)
        for h in SetupHarness.allCases {
            try expectEqual(h.scopes.isEmpty, false)
            try expectEqual(h.supports(.global), true)
        }
    }
]
