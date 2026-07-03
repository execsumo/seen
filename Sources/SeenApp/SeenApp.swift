import SeenKit
import SwiftUI

// Scaffold shell — replaced wholesale by workstream C (menu bar states,
// settings, hotkey, composition root). Exists so the target builds from day 1.
@main
struct SeenAppMain: App {
    var body: some Scene {
        MenuBarExtra("Seen", systemImage: "eye") {
            Text("Seen \(Seen.version) — scaffold")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
