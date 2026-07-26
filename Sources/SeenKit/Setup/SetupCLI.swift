import Foundation

/// Locating a harness's own CLI on `PATH`, for the harnesses that register their
/// MCP server through a command rather than a config file.
public struct SetupCLI {
    public static func resolveExecutable(
        named name: String,
        pathEnv: String?,
        isExecutable: (String) -> Bool
    ) -> String? {
        guard let pathEnv = pathEnv else { return nil }

        let paths = pathEnv.split(separator: ":").map { String($0) }
        for p in paths {
            let u = URL(fileURLWithPath: p).appendingPathComponent(name)
            if isExecutable(u.path) {
                return u.path
            }
        }

        return nil
    }
}
