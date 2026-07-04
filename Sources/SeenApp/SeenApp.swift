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
        
        Settings {
            SettingsView()
                .environmentObject(composition)
        }
        
        WindowGroup("Permissions", id: "onboarding") {
            OnboardingView()
                .environmentObject(composition)
        }
    }
}
