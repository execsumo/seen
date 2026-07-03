import Foundation

public enum IconState: Equatable, Sendable {
    case idle
    case recentCapture
    case sessionActive
}

public func iconState(lastCapture: Date?, activeSessions: Int, now: Date) -> IconState {
    if activeSessions > 0 {
        return .sessionActive
    }
    if let lastCapture = lastCapture, now.timeIntervalSince(lastCapture) <= 3.0 {
        return .recentCapture
    }
    return .idle
}
