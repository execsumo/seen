import Foundation
import Observation
import CoreGraphics

/// Liveness of the agent-facing socket server. Drives the "Agent Access"
/// indicator so a green light never lies about a socket that failed to bind.
public enum ServerStatus: Equatable, Sendable {
    case starting
    case running
    case failed(String)
}

@MainActor
@Observable
public final class AppState {
    public var lastCaptureTime: Date?
    public var sessionInfos: [SessionInfo] = []
    public var activeSessions: Int { sessionInfos.count }
    public var hasPermission: Bool = false
    public var permissionPhase: PermissionPhase = .needed
    public var serverStatus: ServerStatus = .starting
    private var permissionRequestedAt: Date?


    private let coordinator: any CaptureCoordinating
    
    public init(coordinator: any CaptureCoordinating) {
        self.coordinator = coordinator
        self.hasPermission = CGPreflightScreenCaptureAccess()
        self.permissionPhase = resolvePermissionPhase(granted: self.hasPermission, requestedAt: nil, now: Date())
        
        Task {
            await coordinator.observeEvents { [weak self] event in
                Task { @MainActor in
                    guard let self = self else { return }
                    switch event {
                    case .captureCompleted(let result):
                        self.lastCaptureTime = result.timestamp
                    case .captureFailed:
                        break
                    case .sessionStarted(let info):
                        if !self.sessionInfos.contains(where: { $0.id == info.id }) {
                            self.sessionInfos.append(info)
                        }
                    case .sessionEnded(let id):
                        self.sessionInfos.removeAll { $0.id == id }
                    }
                }
            }
        }
    }
    
    public func markPermissionRequested(now: Date = Date()) {
        self.permissionRequestedAt = now
        recheckPermission(now: now)
    }
    
    public func recheckPermission(now: Date = Date()) {
        self.hasPermission = CGPreflightScreenCaptureAccess()
        self.permissionPhase = resolvePermissionPhase(granted: self.hasPermission, requestedAt: self.permissionRequestedAt, now: now)
    }
}
