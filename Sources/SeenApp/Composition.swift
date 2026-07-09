import Foundation
import SeenKit

/// The composition root: the one place concrete SeenKit implementations are
/// assembled behind the Domain protocols the UI depends on.
@MainActor
public final class Composition: ObservableObject {
    public let coordinator: any CaptureCoordinating
    public let settings: AppSettings
    public let pipeline: PushPipeline
    public let appState: AppState
    public let hotkeyManager: HotkeyManager
    public let capturer: any ScreenCapturing
    public let sessionManager: any SessionManaging

    private let server: UDSHTTPServer

    public init() {
        let settings = AppSettings()
        self.settings = settings
        let configurationProvider = settings.configurationProvider

        let capturer = ScreenCaptureKitCapturer()
        let coordinator = CaptureCoordinator(
            capturer: capturer,
            recognizer: VisionTextRecognizer(),
            encoder: ImageIOEncoder(),
            store: DirectoryCaptureStore(configurationProvider: configurationProvider),
            configurationProvider: configurationProvider
        )
        self.coordinator = coordinator
        self.capturer = capturer

        // Session lifecycle events fan out through the coordinator's observers
        // so the menu bar icon reflects them alongside one-shot captures.
        let sessionManager = SessionManager(
            coordinator: coordinator,
            eventSink: { event in Task { await coordinator.emit(event) } }
        )
        self.sessionManager = sessionManager

        self.pipeline = PushPipeline()
        self.appState = AppState(coordinator: coordinator)
        self.hotkeyManager = HotkeyManager(coordinator: coordinator, settings: settings, pipeline: pipeline)
        self.hotkeyManager.register()

        // Serve the agent-facing socket API for the app's lifetime.
        let server = UDSHTTPServer(router: APIRouter(
            coordinator: coordinator,
            sessions: sessionManager,
            capturer: capturer,
            configurationProvider: configurationProvider
        ))
        self.server = server
        let appState = self.appState
        Task {
            do {
                try await server.start()
                await MainActor.run { appState.serverStatus = .running }
            } catch {
                NSLog("Seen: failed to start API server: \(error)")
                await MainActor.run { appState.serverStatus = .failed(error.localizedDescription) }
            }
        }
    }
}
