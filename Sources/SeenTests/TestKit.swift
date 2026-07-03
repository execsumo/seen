import Foundation

// Minimal assertion kit. XCTest/swift-testing are unavailable with Command
// Line Tools alone, so tests are plain Swift run by `swift run SeenTests`.
// Each test file exposes a `[TestCase]` array; register it in AllTests.swift.

struct TestCase: Sendable {
    let name: String
    let body: @Sendable () async throws -> Void

    init(_ name: String, _ body: @escaping @Sendable () async throws -> Void) {
        self.name = name
        self.body = body
    }
}

struct ExpectationFailure: Error, CustomStringConvertible {
    let message: String
    let file: StaticString
    let line: UInt

    var description: String { "\(file):\(line): \(message)" }
}

func expect(
    _ condition: Bool,
    _ message: @autoclosure () -> String = "expected condition to be true",
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    if !condition {
        throw ExpectationFailure(message: message(), file: file, line: line)
    }
}

func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    if actual != expected {
        throw ExpectationFailure(
            message: "expected \(String(reflecting: expected)), got \(String(reflecting: actual))",
            file: file, line: line
        )
    }
}

/// Asserts that `body` throws. Returns the error for further inspection.
@discardableResult
func expectThrows(
    _ body: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async throws -> any Error {
    do {
        try await body()
    } catch {
        return error
    }
    throw ExpectationFailure(message: "expected an error to be thrown", file: file, line: line)
}
