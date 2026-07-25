import Foundation

public struct SetupClaude {
    public static let arguments: [String] = ["mcp", "add", "seen", "--", "seen", "mcp"]
    
    public static func resolveExecutable(pathEnv: String?, isExecutable: (String) -> Bool) -> String? {
        guard let pathEnv = pathEnv else { return nil }
        
        let paths = pathEnv.split(separator: ":").map { String($0) }
        for p in paths {
            let u = URL(fileURLWithPath: p).appendingPathComponent("claude")
            if isExecutable(u.path) {
                return u.path
            }
        }
        
        return nil
    }
}
