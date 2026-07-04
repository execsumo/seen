import Foundation

public actor SessionManager: SessionManaging {
    private var sessions: [UUID: SessionState] = [:]
    
    private struct SessionState {
        var info: SessionInfo
        var task: Task<Void, Never>?
    }
    
    public let coordinator: any CaptureCoordinating
    public let eventSink: @Sendable (CaptureEvent) -> Void
    public let sleepFn: @Sendable (TimeInterval) async throws -> Void
    
    public init(
        coordinator: any CaptureCoordinating,
        eventSink: @escaping @Sendable (CaptureEvent) -> Void = { _ in },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.coordinator = coordinator
        self.eventSink = eventSink
        self.sleepFn = sleep
    }
    
    public func start(_ request: SessionRequest) async throws -> SessionInfo {
        try SessionLimits.validate(request)
        
        if sessions.count >= SessionLimits.maxConcurrentSessions {
            throw SeenError.sessionLimitExceeded("Maximum concurrent sessions (\(SessionLimits.maxConcurrentSessions)) reached")
        }
        
        let id = UUID()
        let now = Date()
        let info = SessionInfo(
            id: id,
            request: request,
            startedAt: now,
            endsAt: now.addingTimeInterval(request.duration),
            captureCount: 0
        )
        
        var state = SessionState(info: info)
        let task = Task<Void, Never> { [weak self] in
            await self?.runSession(id: id, request: request, endsAt: info.endsAt)
        }
        state.task = task
        sessions[id] = state
        
        eventSink(.sessionStarted(info))
        return info
    }
    
    public func stop(id: UUID) async throws {
        guard let state = sessions[id] else {
            throw SeenError.sessionNotFound(id)
        }
        state.task?.cancel()
        removeSession(id: id)
    }
    
    public func activeSessions() -> [SessionInfo] {
        return sessions.values.map { $0.info }.sorted { $0.startedAt < $1.startedAt }
    }
    
    private func runSession(id: UUID, request: SessionRequest, endsAt: Date) async {
        var failures = 0
        
        while !Task.isCancelled {
            // Check if duration elapsed
            if Date() >= endsAt {
                break
            }
            
            // Check cap
            guard let currentState = sessions[id] else { break }
            if currentState.info.captureCount >= SessionLimits.maxCapturesPerSession {
                break
            }
            
            do {
                let result = try await coordinator.perform(request.capture)
                failures = 0
                
                // Update count and emit completion event
                if var state = sessions[id] {
                    state.info.captureCount += 1
                    sessions[id] = state
                    eventSink(.captureCompleted(result))
                }
            } catch {
                failures += 1
                eventSink(.captureFailed(error.localizedDescription))
                if failures >= 3 {
                    break
                }
            }
            
            do {
                try await sleepFn(request.interval)
            } catch {
                break // Cancelled
            }
        }
        
        removeSession(id: id)
    }
    
    private func removeSession(id: UUID) {
        if sessions.removeValue(forKey: id) != nil {
            eventSink(.sessionEnded(id: id))
        }
    }
}
