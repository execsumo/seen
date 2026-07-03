import Foundation
import SeenKit

// INTEGRATION-SWAP: Replace with real implementations at integration
public struct PlaceholderCapturer: ScreenCapturing {
    public init() {}
    public func displays() async throws -> [DisplayInfo] { [] }
    public func applications() async throws -> [AppWindowInfo] { [] }
    public func capture(_ target: CaptureRequest.Target) async throws -> [CapturedFrame] { [] }
    public func hasScreenRecordingPermission() async -> Bool { false }
}

public struct PlaceholderCoordinator: CaptureCoordinating {
    public init() {}
    public func perform(_ request: CaptureRequest) async throws -> CaptureResult {
        CaptureResult(items: [], timestamp: Date())
    }
    public func observeEvents(_ handler: @escaping @Sendable (CaptureEvent) -> Void) async {}
}

public struct PlaceholderSessionManager: SessionManaging {
    public init() {}
    public func start(_ request: SessionRequest) async throws -> SessionInfo {
        SessionInfo(id: UUID(), request: request, startedAt: Date(), endsAt: Date().addingTimeInterval(request.duration), captureCount: 0)
    }
    public func stop(id: UUID) async throws {}
    public func activeSessions() async -> [SessionInfo] { [] }
}

@MainActor
public final class Composition: ObservableObject {
    public let coordinator: any CaptureCoordinating
    public let settings: AppSettings
    public let pipeline: PushPipeline
    public let appState: AppState
    public let hotkeyManager: HotkeyManager
    public let capturer: any ScreenCapturing
    public let sessionManager: any SessionManaging
    
    public init() {
        self.settings = AppSettings()
        // INTEGRATION-SWAP: Replace with real dependencies at integration
        let placeholderCoordinator = PlaceholderCoordinator()
        self.coordinator = placeholderCoordinator
        self.capturer = PlaceholderCapturer()
        self.sessionManager = PlaceholderSessionManager()
        
        self.pipeline = PushPipeline()
        self.appState = AppState(coordinator: placeholderCoordinator)
        self.hotkeyManager = HotkeyManager(coordinator: placeholderCoordinator, settings: settings, pipeline: pipeline)
        
        self.hotkeyManager.register()
    }
}
