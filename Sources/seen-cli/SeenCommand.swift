import ArgumentParser
import Foundation
import SeenKit

@main
struct SeenCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "seen",
        abstract: "CLI for Seen — the vision bridge.",
        subcommands: [
            Health.self, Targets.self, Capture.self, Watch.self, Open.self, MCP.self
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
