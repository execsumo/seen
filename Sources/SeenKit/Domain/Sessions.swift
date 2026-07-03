import Foundation

/// A request to capture repeatedly on an interval.
public struct SessionRequest: Sendable, Codable, Equatable {
    /// Seconds between captures.
    public var interval: TimeInterval
    /// Total lifetime of the session in seconds.
    public var duration: TimeInterval
    public var capture: CaptureRequest

    public init(interval: TimeInterval, duration: TimeInterval, capture: CaptureRequest = CaptureRequest()) {
        self.interval = interval
        self.duration = duration
        self.capture = capture
    }
}

public struct SessionInfo: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var request: SessionRequest
    public var startedAt: Date
    public var endsAt: Date
    public var captureCount: Int

    public init(id: UUID, request: SessionRequest, startedAt: Date, endsAt: Date, captureCount: Int) {
        self.id = id
        self.request = request
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.captureCount = captureCount
    }
}

/// Hard safety caps on interval capture. Compiled in deliberately — these are
/// NOT configurable via the API, the CLI, MCP, or Settings, so no agent can
/// talk the daemon into a runaway capture loop. The caps compose with AND:
/// a 5 s interval is further limited by the 200-capture cap (~16 min).
public enum SessionLimits {
    public static let minInterval: TimeInterval = 5
    public static let maxDuration: TimeInterval = 30 * 60
    public static let maxConcurrentSessions = 2
    public static let maxCapturesPerSession = 200

    /// Rejects (never clamps) out-of-bounds requests with an explicit error,
    /// so callers always learn the real limit instead of getting silently
    /// different behavior.
    public static func validate(_ request: SessionRequest) throws {
        guard request.interval >= minInterval else {
            throw SeenError.sessionLimitExceeded(
                "interval \(request.interval)s is below the minimum of \(Int(minInterval))s")
        }
        guard request.duration > 0 else {
            throw SeenError.sessionLimitExceeded("duration must be positive")
        }
        guard request.duration <= maxDuration else {
            throw SeenError.sessionLimitExceeded(
                "duration \(request.duration)s exceeds the maximum of \(Int(maxDuration))s")
        }
        let plannedCaptures = Int(request.duration / request.interval) + 1
        guard plannedCaptures <= maxCapturesPerSession else {
            throw SeenError.sessionLimitExceeded(
                "\(plannedCaptures) planned captures exceed the per-session cap of \(maxCapturesPerSession); shorten the duration or lengthen the interval")
        }
    }
}

public protocol SessionManaging: Sendable {
    /// Validates against `SessionLimits` (including the concurrent-session
    /// cap) and starts the capture loop. Throws `SeenError.sessionLimitExceeded`.
    func start(_ request: SessionRequest) async throws -> SessionInfo
    /// Throws `SeenError.sessionNotFound` for unknown or finished sessions.
    func stop(id: UUID) async throws
    func activeSessions() async -> [SessionInfo]
}
