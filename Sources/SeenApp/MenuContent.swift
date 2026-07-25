import SwiftUI
import AppKit
import SeenKit

/// The menu-bar dropdown, rendered as a Paper-styled panel
/// (`.menuBarExtraStyle(.window)`). Built for the human at the keyboard —
/// agents use the socket API, MCP, or CLI, never this surface.
public struct MenuContent: View {
    @EnvironmentObject var composition: Composition
    @Environment(\.openWindow) private var openWindow
    @State private var apps: [AppWindowInfo] = []
    @State private var now = Date()

    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    public init() {}

    private var state: IconState {
        iconState(lastCapture: composition.appState.lastCaptureTime,
                  activeSessions: composition.appState.activeSessions,
                  now: now)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)

            SeenTheme.Paper.borderSoft.frame(height: 0.5)

            // Capture actions
            VStack(spacing: 1) {
                MenuBarRow(title: "Capture Now",
                           icon: "camera.viewfinder",
                           hotkey: Hotkey.display(keyCode: composition.settings.hotkeyCode,
                                                  carbonModifiers: composition.settings.hotkeyModifiers)) {
                    capture(target: nil)
                }
                captureAppMenu
                MenuBarRow(title: "Open Screenshots Folder", icon: "folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: composition.settings.saveDirectoryPath))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)

            // Active interval sessions
            if !composition.appState.sessionInfos.isEmpty {
                SeenTheme.Paper.borderSoft.frame(height: 0.5)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Active Sessions")
                        .font(.system(size: 10, weight: .bold))
                        .kerning(0.5)
                        .foregroundStyle(SeenTheme.Paper.mute)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                    ForEach(composition.appState.sessionInfos) { info in
                        MenuBarRow(title: "Stop session \(info.id.uuidString.prefix(4))",
                                   icon: "stop.circle", accent: true) {
                            Task { try? await composition.sessionManager.stop(id: info.id) }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SeenTheme.Paper.borderSoft.frame(height: 0.5)

            // Footer
            VStack(spacing: 1) {
                MenuBarRow(title: "Settings…", icon: "gearshape") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }

                MenuBarRow(title: "Quit Seen", icon: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .frame(width: 280)
        .background(SeenTheme.Paper.bg)
        .onReceive(ticker) { now = $0 }
        .onAppear(perform: loadApps)
    }

    // MARK: Status header

    @ViewBuilder
    private var header: some View {
        switch state {
        case .sessionActive:
            StatusHeaderCard(dotColor: SeenTheme.Paper.bad, pulsing: true,
                             title: "Capturing on a schedule",
                             subtitle: "\(composition.appState.activeSessions) active session\(composition.appState.activeSessions == 1 ? "" : "s")")
        case .recentCapture:
            StatusHeaderCard(dotColor: SeenTheme.Paper.accent, pulsing: false,
                             title: "Screenshot captured",
                             subtitle: "Saved to your screenshots folder")
        case .idle:
            StatusHeaderCard(dotColor: idleDotColor, pulsing: false,
                             title: idleTitle,
                             subtitle: idleSubtitle)
        }
    }

    // Title, subtitle, and dot all branch the same way — permission first, then
    // server status — so they never contradict each other.

    private var idleTitle: String {
        guard composition.appState.hasPermission else { return "Screen Recording Needed" }
        switch composition.appState.serverStatus {
        case .running:  return "Agent Bridge Running"
        case .starting: return "Starting Agent Bridge…"
        case .failed:   return "Agent Bridge Offline"
        }
    }

    private var idleDotColor: Color {
        // No Screen Recording → nothing captures at all: red, not amber. Amber is
        // reserved for states where capture still works (bridge starting/offline).
        guard composition.appState.hasPermission else { return SeenTheme.Paper.bad }
        switch composition.appState.serverStatus {
        case .running:  return SeenTheme.Paper.good
        case .starting: return SeenTheme.Paper.warn
        case .failed:   return SeenTheme.Paper.warn // capture still works, but the bridge is down — amber, not green
        }
    }

    private var idleSubtitle: String {
        guard composition.appState.hasPermission else { return "Grant it so agents can see your screen" }
        switch composition.appState.serverStatus {
        case .running:  return "Agents can see your screen"
        case .starting: return "Starting agent bridge…"
        case .failed:   return "Capture still works via hotkey & menu"
        }
    }

    // MARK: Capture App menu

    private var captureAppMenu: some View {
        Menu {
            if apps.isEmpty {
                Text("No apps available")
            } else {
                ForEach(apps, id: \.id) { appInfo in
                    Button(appInfo.appName) { capture(target: .app(appInfo.appName)) }
                }
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "square.on.square")
                    .font(.system(size: 12))
                    .foregroundStyle(SeenTheme.Paper.ink2)
                    .frame(width: 18, alignment: .center)
                Text("Capture App")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SeenTheme.Paper.ink)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .menuStyle(.button)
        .buttonStyle(MenuBarRowStyle())
        .menuIndicator(.hidden)
    }

    // MARK: Actions

    private func capture(target: CaptureRequest.Target?) {
        Task {
            let request = HumanCapture.request(target: target,
                                               output: composition.settings.captureOutput)
            if let result = try? await composition.coordinator.perform(request) {
                try? await composition.pipeline.push(result, to: .clipboard)
            }
        }
    }

    private func loadApps() {
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
}
