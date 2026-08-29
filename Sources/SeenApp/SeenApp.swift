import SwiftUI
import AppKit
import SeenKit

@main
struct SeenAppMain: App {
    @StateObject private var composition = Composition()

    init() {
        // DESIGN.md ships one palette, anchored on a near-black ground. Pinning
        // the whole process to dark keeps AppKit-drawn surfaces the app doesn't
        // style itself — submenus, the folder picker — on the same ground as the
        // SwiftUI chrome.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)

        // Register the bundled JetBrains Mono faces before the first view body
        // resolves a font, so nothing renders a frame in the fallback face.
        _ = SeenFonts.isAvailable
    }

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
