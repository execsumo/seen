import Foundation
import Observation
import CoreGraphics

@MainActor
@Observable
public final class AppState {
    public var lastCaptureTime: Date?
    public var sessionInfos: [SessionInfo] = []
    public var activeSessions: Int { sessionInfos.count }
    public var hasPermission: Bool = false
    
    private let coordinator: any CaptureCoordinating
    
    public init(coordinator: any CaptureCoordinating) {
        self.coordinator = coordinator
        self.hasPermission = CGPreflightScreenCaptureAccess()
        
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
    
    public func recheckPermission() {
        self.hasPermission = CGPreflightScreenCaptureAccess()
    }
}
