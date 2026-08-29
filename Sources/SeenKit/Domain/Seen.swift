import Foundation

/// Global constants for the Seen package.
public enum Seen {
    /// Reported by `GET /health` and MCP `initialize` (`serverInfo.version`).
    /// Hand-maintained: nothing derives it from the git tag or the bundle's
    /// CFBundleShortVersionString, so it must be bumped as part of cutting a
    /// release or the wire surface reports a stale version. It sat at "0.1.0"
    /// through v0.1.1 and v0.1.2 for exactly that reason.
    public static let version = "0.1.4"
}

/// Well-known filesystem locations shared by the app, the CLI, and the MCP shim.
public enum SeenPaths {
    /// `~/Library/Application Support/Seen`
    public static var applicationSupportDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Seen", isDirectory: true)
    }

    /// Path of the Unix domain socket the daemon listens on.
    /// Override with the `SEEN_SOCKET` environment variable (used by tests).
    public static var socketPath: String {
        if let override = ProcessInfo.processInfo.environment["SEEN_SOCKET"], !override.isEmpty {
            return override
        }
        return applicationSupportDirectory.appendingPathComponent("seen.sock").path
    }

    /// Default directory captures are saved to when the user hasn't chosen one.
    /// Kept under Application Support (not `~/Pictures`) so writing captures
    /// never triggers the TCC "Pictures folder" prompt — Seen should only ever
    /// need Screen Recording. Users can still point this at ~/Pictures in
    /// Settings if they want.
    public static var defaultSaveDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Captures", isDirectory: true)
    }
}
