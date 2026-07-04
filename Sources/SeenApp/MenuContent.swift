import SwiftUI
import AppKit
import SeenKit

public struct MenuContent: View {
    @EnvironmentObject var composition: Composition
    @State private var apps: [AppWindowInfo] = []
    
    public init() {}
    
    public var body: some View {
        Button("Capture Now") {
            Task {
                var request = CaptureRequest()
                request.output = composition.settings.captureOutput
                if let result = try? await composition.coordinator.perform(request) {
                    try? await composition.pipeline.push(result, to: composition.settings.pushDestination)
                }
            }
        }
        
        Menu("Capture App") {
            if apps.isEmpty {
                Text("No apps available")
            } else {
                ForEach(apps, id: \.id) { appInfo in
                    Button(appInfo.appName) {
                        Task {
                            var request = CaptureRequest()
                            request.target = .app(appInfo.appName)
                            request.output = composition.settings.captureOutput
                            if let result = try? await composition.coordinator.perform(request) {
                                try? await composition.pipeline.push(result, to: composition.settings.pushDestination)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            Task {
                do {
                    let fetched = try await composition.capturer.applications()
                    var seen = Set<String>()
                    self.apps = fetched.filter {
                        if seen.contains($0.appName) { return false }
                        seen.insert($0.appName)
                        return true
                    }
                } catch {
                    print("Failed to list apps: \(error)")
                }
            }
        }
        
        Button("Open Screenshots Folder") {
            let url = URL(fileURLWithPath: composition.settings.saveDirectoryPath)
            NSWorkspace.shared.open(url)
        }
        
        if composition.appState.activeSessions > 0 {
            Divider()
            Text("\(composition.appState.activeSessions) Active Session(s)")
            ForEach(composition.appState.sessionInfos) { info in
                Button("Stop Session \(info.id.uuidString.prefix(4))") {
                    Task { try? await composition.sessionManager.stop(id: info.id) }
                }
            }
        }
        
        Divider()
        
        Text("API: ~/Library/Application Support/Seen/seen.sock")
        Button("Copy curl example") {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString("curl --unix-socket ~/Library/Application\\ Support/Seen/seen.sock http://seen/capture", forType: .string)
        }
        
        Divider()
        
        SettingsLink {
            Text("Settings…")
        }
        
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
