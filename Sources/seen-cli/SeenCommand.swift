import ArgumentParser
import SeenKit

// Scaffold entry point — workstream B replaces this with the real subcommand
// tree (capture, watch, targets, health, open, mcp).
@main
struct SeenCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "seen",
        abstract: "Client for the Seen capture daemon.",
        version: Seen.version
    )

    func run() async throws {
        print("seen \(Seen.version) — scaffold; subcommands arrive with workstream B")
        print("socket: \(SeenPaths.socketPath)")
    }
}
