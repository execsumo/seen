import Foundation

public struct PushTemplate: Sendable {
    public static func render(_ template: String, paths: [String], text: String?) -> String {
        let pathEscaped = paths.first.map { escapeForShell($0) } ?? "''"
        let pathsEscaped = paths.isEmpty ? "''" : paths.map { escapeForShell($0) }.joined(separator: " ")
        let textEscaped = escapeForShell(text ?? "")
        
        var result = template
        result = result.replacingOccurrences(of: "{path}", with: pathEscaped)
        result = result.replacingOccurrences(of: "{paths}", with: pathsEscaped)
        result = result.replacingOccurrences(of: "{text}", with: textEscaped)
        return result
    }
    
    private static func escapeForShell(_ string: String) -> String {
        let escaped = string.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
