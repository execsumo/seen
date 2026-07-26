import Foundation

/// Where a harness stores its configuration. `global` covers every project on
/// the machine; `project` is scoped to the workspace you run setup from.
public enum SetupScope: String, CaseIterable, Sendable {
    case global
    case project
}

/// The agent harnesses `seen setup` knows how to configure.
///
/// Each case is the whole integration for that harness — how its MCP server is
/// registered, and where its skill file goes — so adding a harness is a matter
/// of extending this table rather than touching the command layer. Everything
/// here is a pure function of the scope and the two roots, which is what lets
/// the paths be tested without writing anywhere near a real home directory.
public enum SetupHarness: String, CaseIterable, Sendable {
    case claude
    case codex
    case cursor
    case antigravity

    /// How a harness's MCP server registration is performed.
    public enum MCPInstall: Equatable, Sendable {
        /// The harness ships its own CLI; shell out to it.
        case cli(executable: String, arguments: [String])
        /// The harness reads a JSON file with an `mcpServers` object; merge into it.
        case jsonMerge(URL)
    }

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .antigravity: return "Antigravity"
        }
    }

    /// Scopes this harness can actually express. Codex stores both its MCP
    /// servers (`~/.codex/config.toml`) and its skills (`$CODEX_HOME/skills`)
    /// globally and has no per-workspace equivalent, so `--project` is rejected
    /// rather than silently ignored.
    public var scopes: [SetupScope] {
        switch self {
        case .codex: return [.global]
        case .claude, .cursor, .antigravity: return [.global, .project]
        }
    }

    public func supports(_ scope: SetupScope) -> Bool {
        scopes.contains(scope)
    }

    public func mcpInstall(scope: SetupScope, home: URL, workspace: URL) -> MCPInstall {
        switch self {
        case .claude:
            // claude's own scope vocabulary: `user` is machine-wide, `project`
            // writes a shareable .mcp.json in the workspace. Its default is
            // `local` (private, cwd-bound), which matches neither of ours.
            let claudeScope = scope == .global ? "user" : "project"
            return .cli(
                executable: "claude",
                arguments: ["mcp", "add", "seen", "-s", claudeScope, "--", "seen", "mcp"]
            )
        case .codex:
            return .cli(executable: "codex", arguments: ["mcp", "add", "seen", "--", "seen", "mcp"])
        case .cursor:
            let base = scope == .global ? home.appendingPathComponent(".cursor")
                                        : workspace.appendingPathComponent(".cursor")
            return .jsonMerge(base.appendingPathComponent("mcp.json"))
        case .antigravity:
            let path = scope == .global
                ? home.appendingPathComponent(".gemini/config/mcp_config.json")
                : workspace.appendingPathComponent(".agents/mcp_config.json")
            return .jsonMerge(path)
        }
    }

    /// Destination for `SKILL.md`, or nil for a harness with no skills concept.
    public func skillDestination(scope: SetupScope, home: URL, workspace: URL) -> URL? {
        switch self {
        case .claude:
            let base = scope == .global ? home.appendingPathComponent(".claude")
                                        : workspace.appendingPathComponent(".claude")
            return base.appendingPathComponent("skills/seen/SKILL.md")
        case .codex:
            return home.appendingPathComponent(".codex/skills/seen/SKILL.md")
        case .cursor:
            // Cursor has mcp.json and hooks.json but no skills directory.
            return nil
        case .antigravity:
            let base = scope == .global ? home.appendingPathComponent(".gemini/config")
                                        : workspace.appendingPathComponent(".agents")
            return base.appendingPathComponent("skills/seen/SKILL.md")
        }
    }

    /// Shown after a change lands, when the harness only reads its config at launch.
    public var restartHint: String? {
        switch self {
        case .claude: return "Restart Claude Code to load the seen MCP server."
        case .codex: return "Restart Codex to load the seen MCP server."
        case .cursor: return "Restart Cursor to apply the changes."
        case .antigravity: return "Restart Antigravity to apply the changes."
        }
    }
}
