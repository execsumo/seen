import Foundation

public enum PermissionPhase: Equatable, Sendable {
    case needed                    // never requested, or request not yet made
    case requestedPendingRestart   // asked, macOS hasn't applied it to this process
    case granted
}

public func resolvePermissionPhase(granted: Bool, requestedAt: Date?, now: Date) -> PermissionPhase {
    if granted {
        return .granted
    }
    
    guard let requestedAt = requestedAt else {
        return .needed
    }
    
    if now.timeIntervalSince(requestedAt) >= 2.0 {
        return .requestedPendingRestart
    } else {
        return .needed
    }
}
