import Foundation

public protocol ProcessRunning: Sendable {
    func run(_ executable: String, _ arguments: [String]) async throws -> Int32
}

public struct DefaultProcessRunner: ProcessRunning {
    public init() {}
    
    public func run(_ executable: String, _ arguments: [String]) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
