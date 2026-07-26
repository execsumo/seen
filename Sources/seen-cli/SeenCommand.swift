import ArgumentParser
import Foundation
import SeenKit

@main
struct SeenCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "seen",
        abstract: "CLI for Seen — the vision bridge.",
        subcommands: [
            Health.self, Targets.self, Capture.self, Watch.self, Open.self, MCP.self, Setup.self
        ]
    )
}

// MARK: - Helpers

func parseTimeInterval(_ str: String) throws -> TimeInterval {
    if str.hasSuffix("s") {
        if let val = Double(str.dropLast()) { return val }
    } else if str.hasSuffix("m") {
        if let val = Double(str.dropLast()) { return val * 60 }
    } else if let val = Double(str) {
        return val
    }
    throw ValidationError("Invalid time interval format. Use '10s', '5m', or a number of seconds.")
}

extension CaptureRequest.Target {
    static func from(app: String?, display: UInt32?, window: UInt32?) throws -> CaptureRequest.Target {
        if let a = app { return .app(a) }
        if let d = display { return .display(d) }
        if let w = window { return .window(w) }
        return .allDisplays
    }
}

// MARK: - Commands

struct Health: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check server health.")
    
    mutating func run() async throws {
        let client = UDSAPIClient()
        do {
            let res = try await client.health()
            print(res)
        } catch {
            print("Seen isn't running — launch the Seen app")
            throw ExitCode.failure
        }
    }
}

struct Targets: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List available targets.")
    
    @Flag(name: .long, help: "Output as JSON")
    var json = false
    
    mutating func run() async throws {
        let client = UDSAPIClient()
        do {
            let d = try await client.displays()
            let a = try await client.apps()
            if json {
                print("{\"displays\": \(d), \"apps\": \(a)}")
            } else {
                print("Displays:\n\(d)\n\nApps:\n\(a)")
            }
        } catch {
            print("Seen isn't running — launch the Seen app")
            throw ExitCode.failure
        }
    }
}

struct Capture: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Capture the screen.")
    
    @Option(name: .long) var app: String?
    @Option(name: .long) var display: UInt32?
    @Option(name: .long) var window: UInt32?
    
    @Flag(name: .long) var imageOnly = false
    @Flag(name: .long) var ocrOnly = false
    
    @Option(name: .long) var format: ImageFormat?
    @Option(name: .long) var quality: Double?
    @Option(name: .long) var maxDimension: Int?
    
    @Flag(name: .long) var json = false
    
    mutating func run() async throws {
        let client = UDSAPIClient()
        var req = CaptureRequest()
        req.target = try CaptureRequest.Target.from(app: app, display: display, window: window)
        
        if imageOnly { req.output = .image }
        else if ocrOnly { req.output = .text }
        else { req.output = .both }
        
        req.format = format
        req.quality = quality
        req.maxDimension = maxDimension
        
        do {
            let res = try await client.capture(req)
            if json {
                let data = try JSONCoding.encoder.encode(res)
                print(String(data: data, encoding: .utf8) ?? "")
            } else {
                for item in res.items {
                    print("Path: \(item.path)")
                    if let text = item.text, !text.isEmpty {
                        print("OCR Text:\n\(text)")
                    }
                }
            }
        } catch {
            print("Seen isn't running — launch the Seen app (or error: \(error))")
            throw ExitCode.failure
        }
    }
}

struct Watch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage interval capture sessions.",
        subcommands: [Start.self, List.self, Stop.self]
    )
    
    struct Start: AsyncParsableCommand {
        @Option(name: .long) var interval: String
        @Option(name: .long) var duration: String
        
        @Option(name: .long) var app: String?
        @Option(name: .long) var display: UInt32?
        @Option(name: .long) var window: UInt32?
        
        mutating func run() async throws {
            let i = try parseTimeInterval(interval)
            let d = try parseTimeInterval(duration)
            
            let client = UDSAPIClient()
            var req = CaptureRequest()
            req.target = try CaptureRequest.Target.from(app: app, display: display, window: window)
            
            let sreq = SessionRequest(interval: i, duration: d, capture: req)
            do {
                let res = try await client.startSession(sreq)
                print("Started session \(res.id.uuidString)")
            } catch {
                print("Error: \(error)")
                throw ExitCode.failure
            }
        }
    }
    
    struct List: AsyncParsableCommand {
        mutating func run() async throws {
            let client = UDSAPIClient()
            do {
                let res = try await client.listSessions()
                print(res)
            } catch {
                print("Error: \(error)")
                throw ExitCode.failure
            }
        }
    }
    
    struct Stop: AsyncParsableCommand {
        @Argument var id: String
        mutating func run() async throws {
            guard let uuid = UUID(uuidString: id) else {
                throw ValidationError("Invalid UUID")
            }
            let client = UDSAPIClient()
            do {
                try await client.stopSession(id: uuid)
                print("Stopped session \(uuid)")
            } catch {
                print("Error: \(error)")
                throw ExitCode.failure
            }
        }
    }
}

struct Open: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Open the screenshots folder.")
    
    mutating func run() async throws {
        let client = UDSAPIClient()
        do {
            let confStr = try await client.config()
            struct Conf: Decodable { var saveDirectoryPath: String }
            if let data = confStr.data(using: .utf8), let c = try? JSONCoding.decoder.decode(Conf.self, from: data) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = [c.saveDirectoryPath]
                try p.run()
                p.waitUntilExit()
            }
        } catch {
            print("Seen isn't running — launch the Seen app")
            throw ExitCode.failure
        }
    }
}

struct MCP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Start the MCP server.")
    
    mutating func run() async throws {
        let client = UDSAPIClient()
        let handler = MCPHandler(client: client)
        
        let handle = FileHandle.standardInput
        
        for try await line in handle.bytes.lines {
            if let data = line.data(using: .utf8) {
                if let response = await handler.handle(data) {
                    if let str = String(data: response, encoding: .utf8) {
                        print(str)
                        fflush(stdout)
                    }
                }
            }
        }
    }
}

extension ImageFormat: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}
/// The outcome of one setup step, so a command that does two things can report
/// each honestly. `alreadyCurrent` is a success: re-running setup on a
/// configured machine must not look like a failure.
enum StepOutcome {
    case applied(String)
    case alreadyCurrent(String)
    case skipped(String)
    case failed(String)

    var line: String {
        switch self {
        case .applied(let m): return "  ✓ \(m)"
        case .alreadyCurrent(let m): return "  · \(m)"
        case .skipped(let m): return "  – \(m)"
        case .failed(let m): return "  ✗ \(m)"
        }
    }

    var isFailure: Bool { if case .failed = self { return true }; return false }
    var changedSomething: Bool { if case .applied = self { return true }; return false }
}

enum SetupRunner {
    /// Runs a harness CLI and captures its output.
    ///
    /// The child must get no terminal. Foundation spawns it into a new process
    /// group, so an inherited tty gets it SIGTTIN/SIGTTOU'd into a stopped state
    /// and waitUntilExit() never returns — that was the v0.1.3 `setup claude`
    /// hang. Null stdin plus one pipe for both streams, drained before the wait.
    static func run(executable: String, arguments: [String]) throws -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments

        let pipe = Pipe()
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (p.terminationStatus, text)
    }

    static func installMCP(_ harness: SetupHarness, scope: SetupScope, configOverride: String?) -> StepOutcome {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        var install = harness.mcpInstall(scope: scope, home: home, workspace: workspace)
        // --config points the JSON merge at an explicit file. Only meaningful for
        // the file-based harnesses; the CLI ones own their own config location.
        if let configOverride = configOverride, case .jsonMerge = install {
            install = .jsonMerge(URL(fileURLWithPath: NSString(string: configOverride).expandingTildeInPath))
        }

        switch install {
        case .cli(let executable, let arguments):
            let resolved = SetupCLI.resolveExecutable(
                named: executable,
                pathEnv: ProcessInfo.processInfo.environment["PATH"]
            ) { FileManager.default.isExecutableFile(atPath: $0) }

            guard let resolved = resolved else {
                let manual = ([executable] + arguments).joined(separator: " ")
                return .failed("MCP: \(executable) not found on PATH. Run it yourself:\n      \(manual)")
            }

            do {
                let result = try run(executable: resolved, arguments: arguments)
                if result.status == 0 {
                    return .applied("MCP: registered with \(harness.displayName)")
                }
                // The harness CLIs exit non-zero on a duplicate add. That's an
                // already-configured machine, not a failure. Matching their
                // message is a heuristic; if it ever stops matching we fall
                // through and surface their own text rather than guessing.
                if result.output.lowercased().contains("already exists") {
                    return .alreadyCurrent("MCP: already registered with \(harness.displayName)")
                }
                return .failed("MCP: \(executable) exited \(result.status)\n      \(result.output)")
            } catch {
                return .failed("MCP: could not run \(executable) — \(error.localizedDescription)")
            }

        case .jsonMerge(let url):
            do {
                let changed = try SetupMCPJSON.merge(into: url)
                return changed ? .applied("MCP: wrote \(url.path)")
                               : .alreadyCurrent("MCP: already configured in \(url.path)")
            } catch {
                return .failed("MCP: \(error.localizedDescription)")
            }
    }
    }

    static func installSkill(_ harness: SetupHarness, scope: SetupScope, yes: Bool) -> StepOutcome {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        guard let destURL = harness.skillDestination(scope: scope, home: home, workspace: workspace) else {
            return .skipped("Skill: \(harness.displayName) has no skills directory")
        }

        let exeURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let sourceURL: URL
        do {
            sourceURL = try SetupSkill.resolveSourcePath(executableURL: exeURL)
        } catch {
            return .failed("Skill: \(error.localizedDescription)")
        }

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                let sourceData = try Data(contentsOf: sourceURL)
                if (try? Data(contentsOf: destURL)) == sourceData {
                    return .alreadyCurrent("Skill: already current at \(destURL.path)")
                }
                if !yes {
                    guard isatty(STDIN_FILENO) == 1 else {
                        return .failed("Skill: \(destURL.path) exists and differs. Re-run with --yes to overwrite.")
                    }
                    print("Skill exists at \(destURL.path). Overwrite? [y/N]: ", terminator: "")
                    fflush(stdout)
                    guard let line = readLine(), line.lowercased().starts(with: "y") else {
                        return .skipped("Skill: left \(destURL.path) unchanged")
                    }
                }
            }

            let changed = try SetupSkill.installSkill(sourceURL: sourceURL, destURL: destURL)
            return changed ? .applied("Skill: installed to \(destURL.path)")
                           : .alreadyCurrent("Skill: already current at \(destURL.path)")
        } catch {
            return .failed("Skill: \(error.localizedDescription)")
        }
    }
}

/// Shared behaviour for the per-harness subcommands. Each one configures
/// everything its harness supports — MCP server and skill — so there is one
/// command per harness rather than one per artifact kind.
protocol HarnessSetupCommand: AsyncParsableCommand {
    static var harness: SetupHarness { get }
    var project: Bool { get }
    var mcpOnly: Bool { get }
    var yes: Bool { get }
    var skillOnly: Bool { get }
    var configOverride: String? { get }
}

// Defaults for harnesses that can't express a flag at all — a harness with no
// skills directory doesn't declare --skill-only or --yes rather than accepting
// them as no-ops.
extension HarnessSetupCommand {
    var yes: Bool { false }
    var skillOnly: Bool { false }
    var configOverride: String? { nil }
}

extension HarnessSetupCommand {
    func runHarnessSetup() throws {
        let harness = Self.harness

        if mcpOnly && skillOnly {
            print("--mcp-only and --skill-only are mutually exclusive.")
            throw ExitCode.failure
        }

        let scope: SetupScope = project ? .project : .global
        guard harness.supports(scope) else {
            print("\(harness.displayName) stores its configuration globally and has no per-project equivalent.")
            print("Re-run without --project.")
            throw ExitCode.failure
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let hasSkill = harness.skillDestination(scope: scope, home: home, workspace: workspace) != nil
        if skillOnly && !hasSkill {
            print("\(harness.displayName) has no skills directory, so --skill-only has nothing to do.")
            throw ExitCode.failure
        }

        print("Configuring \(harness.displayName) (\(scope.rawValue))")

        var outcomes: [StepOutcome] = []
        if !skillOnly {
            outcomes.append(SetupRunner.installMCP(harness, scope: scope, configOverride: configOverride))
        }
        if !mcpOnly { outcomes.append(SetupRunner.installSkill(harness, scope: scope, yes: yes)) }

        for outcome in outcomes { print(outcome.line) }

        if outcomes.contains(where: { $0.isFailure }) {
            throw ExitCode.failure
        }
        if outcomes.contains(where: { $0.changedSomething }), let hint = harness.restartHint {
            print(hint)
        }
    }
}

struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Setup Seen integrations.",
        subcommands: [Claude.self, Codex.self, Cursor.self, Antigravity.self]
    )

    struct Claude: HarnessSetupCommand {
        static let configuration = CommandConfiguration(abstract: "Setup Seen for Claude Code (MCP + skill).")
        static let harness = SetupHarness.claude
        @Flag(name: .long, help: "Configure this project only.") var project = false
        @Flag(name: .long, help: "Overwrite an existing skill file without asking.") var yes = false
        @Flag(name: .customLong("mcp-only"), help: "Register the MCP server only.") var mcpOnly = false
        @Flag(name: .customLong("skill-only"), help: "Install the skill only.") var skillOnly = false
        mutating func run() async throws { try runHarnessSetup() }
    }

    struct Codex: HarnessSetupCommand {
        static let configuration = CommandConfiguration(abstract: "Setup Seen for Codex (MCP + skill).")
        static let harness = SetupHarness.codex
        @Flag(name: .long, help: "Not supported — Codex configures globally.") var project = false
        @Flag(name: .long, help: "Overwrite an existing skill file without asking.") var yes = false
        @Flag(name: .customLong("mcp-only"), help: "Register the MCP server only.") var mcpOnly = false
        @Flag(name: .customLong("skill-only"), help: "Install the skill only.") var skillOnly = false
        mutating func run() async throws { try runHarnessSetup() }
    }

    // Cursor has no skills directory, so it declares neither --skill-only nor
    // --yes: an unhonourable flag is worse absent than accepted-and-ignored.
    struct Cursor: HarnessSetupCommand {
        static let configuration = CommandConfiguration(abstract: "Setup Seen for Cursor (MCP).")
        static let harness = SetupHarness.cursor
        @Flag(name: .long, help: "Configure this project only.") var project = false
        @Flag(name: .customLong("mcp-only"), help: "Register the MCP server only.") var mcpOnly = false
        @Option(name: .long, help: "Write to this config file instead of the default.") var config: String?
        var configOverride: String? { config }
        mutating func run() async throws { try runHarnessSetup() }
    }

    struct Antigravity: HarnessSetupCommand {
        static let configuration = CommandConfiguration(abstract: "Setup Seen for Antigravity (MCP + skill).")
        static let harness = SetupHarness.antigravity
        @Flag(name: .long, help: "Configure this workspace only.") var project = false
        @Flag(name: .long, help: "Overwrite an existing skill file without asking.") var yes = false
        @Flag(name: .customLong("mcp-only"), help: "Register the MCP server only.") var mcpOnly = false
        @Flag(name: .customLong("skill-only"), help: "Install the skill only.") var skillOnly = false
        @Option(name: .long, help: "Write to this config file instead of the default.") var config: String?
        var configOverride: String? { config }
        mutating func run() async throws { try runHarnessSetup() }
    }
}
