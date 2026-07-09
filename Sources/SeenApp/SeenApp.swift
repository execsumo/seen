import SwiftUI
import SeenKit

@main
struct SeenAppMain: App {
    @StateObject private var composition = Composition()
    
    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(composition)
        } label: {
            MenuBarIconContainer(lastCapture: composition.appState.lastCaptureTime, activeSessions: composition.appState.activeSessions)
        }
        .menuBarExtraStyle(.window)

        // A real Window (not the Settings scene) so it can be brought to the
        // front from this LSUIElement accessory app — the Settings scene opens
        // behind the focused app because opening it doesn't activate us.
        Window("Seen Settings", id: "settings") {
            SettingsView()
                .environmentObject(composition)
        }
        .windowResizability(.contentSize)
        
        WindowGroup("Permissions", id: "onboarding") {
            OnboardingView()
                .environmentObject(composition)
        }
    }
}
