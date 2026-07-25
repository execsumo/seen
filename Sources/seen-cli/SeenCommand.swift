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

struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Setup Seen integrations.",
        subcommands: [Claude.self, Cursor.self, Skill.self]
    )
    
    struct Claude: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Setup Seen for Claude.")
        mutating func run() async throws {
            guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else {
                print("claude not found on PATH. Run this command manually:\n  claude mcp add seen -- seen mcp")
                throw ExitCode.failure
            }
            let paths = pathEnv.split(separator: ":").map { String($0) }
            var claudePath: String? = nil
            for p in paths {
                let u = URL(fileURLWithPath: p).appendingPathComponent("claude")
                if FileManager.default.isExecutableFile(atPath: u.path) {
                    claudePath = u.path
                    break
                }
            }
            guard let execPath = claudePath else {
                print("claude not found on PATH. Run this command manually:\n  claude mcp add seen -- seen mcp")
                throw ExitCode.failure
            }
            
            let p = Process()
            p.executableURL = URL(fileURLWithPath: execPath)
            p.arguments = ["mcp", "add", "seen", "--", "seen", "mcp"]
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                throw ExitCode(p.terminationStatus)
            }
        }
    }
    
    struct Cursor: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Setup Seen for Cursor.")
        
        @Flag(name: .long) var project = false
        @Option(name: .long) var config: String?
        
        mutating func run() async throws {
            let url: URL
            if let config = config {
                url = URL(fileURLWithPath: config)
            } else if project {
                url = URL(fileURLWithPath: "./.cursor/mcp.json")
            } else {
                url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor/mcp.json")
            }
            
            do {
                let changed = try SetupCursor.merge(into: url)
                if changed {
                    print("Updated \(url.path)")
                    print("Please restart Cursor to apply the changes.")
                } else {
                    print("Already configured in \(url.path)")
                }
            } catch {
                print("Error: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }
    
    struct Skill: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Setup Seen skill.")
        
        @Option(name: .long) var dest: String?
        @Flag(name: .long) var project = false
        @Flag(name: .long) var yes = false
        
        mutating func run() async throws {
            let exeURL = URL(fileURLWithPath: CommandLine.arguments[0])
            let sourceURL: URL
            do {
                sourceURL = try SetupSkill.resolveSourcePath(executableURL: exeURL)
            } catch {
                print("Error finding SKILL.md: \(error.localizedDescription)")
                throw ExitCode.failure
            }
            
            let destURL: URL
            if let dest = dest {
                let expanded = NSString(string: dest).expandingTildeInPath
                destURL = URL(fileURLWithPath: expanded).appendingPathComponent("seen/SKILL.md")
            } else if project {
                destURL = URL(fileURLWithPath: "./.claude/skills/seen/SKILL.md")
            } else if isatty(STDIN_FILENO) == 0 && !yes {
                print("Cannot prompt interactively. Use --dest or --yes to specify destination.")
                print("Example: seen setup skill --yes")
                throw ExitCode.failure
            } else if isatty(STDIN_FILENO) == 1 && !yes {
                print("Install Seen skill?")
                print("1. Claude Code, all projects (~/.claude/skills)")
                print("2. Claude Code, this project only (./.claude/skills)")
                print("3. Another path")
                print("4. Skip")
                print("Choice [1]: ", terminator: "")
                fflush(stdout)
                
                guard let line = readLine() else { throw ExitCode.failure }
                let choice = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if choice == "1" || choice.isEmpty {
                    destURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills/seen/SKILL.md")
                } else if choice == "2" {
                    destURL = URL(fileURLWithPath: "./.claude/skills/seen/SKILL.md")
                } else if choice == "3" {
                    print("Enter path: ", terminator: "")
                    fflush(stdout)
                    guard let p = readLine(), !p.isEmpty else { throw ExitCode.failure }
                    let expanded = NSString(string: p).expandingTildeInPath
                    destURL = URL(fileURLWithPath: expanded).appendingPathComponent("seen/SKILL.md")
                } else {
                    return
                }
            } else {
                destURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills/seen/SKILL.md")
            }
            
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    let sourceData = try Data(contentsOf: sourceURL)
                    let destData = try? Data(contentsOf: destURL)
                    if sourceData == destData {
                        print("Skill already installed and identical at \(destURL.path)")
                        return
                    }
                    if !yes {
                        if isatty(STDIN_FILENO) == 1 {
                            print("File exists at \(destURL.path). Overwrite? [y/N]: ", terminator: "")
                            fflush(stdout)
                            guard let line = readLine(), line.lowercased().starts(with: "y") else {
                                return
                            }
                        } else {
                            print("File exists. Use --yes to overwrite.")
                            throw ExitCode.failure
                        }
                    }
                }
                
                let changed = try SetupSkill.installSkill(sourceURL: sourceURL, destURL: destURL)
                if changed {
                    print("Installed skill to \(destURL.path)")
                }
            } catch {
                print("Error: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }
}
