import SwiftUI
import AppKit
import SeenKit

// MARK: - Settings shell

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, hotkey, destination, permissions
    var id: String { rawValue }

    var label: String {
        switch self {
        case .general:     return "General"
        case .hotkey:      return "Hotkey"
        case .destination: return "Destination"
        case .permissions: return "Permissions"
        }
    }

    var icon: String {
        switch self {
        case .general:     return "gearshape"
        case .hotkey:      return "keyboard"
        case .destination: return "arrow.up.forward.app"
        case .permissions: return "lock.shield"
        }
    }
}

public struct SettingsView: View {
    @EnvironmentObject var composition: Composition
    @State private var tab: SettingsTab = .general

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
        }
        .frame(width: 660, height: 480)
        .background(SeenTheme.Paper.bg)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SeenMark(size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Seen")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SeenTheme.Paper.ink)
                    Text(appVersion)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(SeenTheme.Paper.mute)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 12)

            SeenTheme.Paper.border.frame(height: 0.5)

            VStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { item in
                    sidebarItem(item)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)

            Spacer()
        }
        .frame(width: 184)
        .background(SeenTheme.Paper.sidebar)
        .overlay(alignment: .trailing) { SeenTheme.Paper.border.frame(width: 0.5) }
    }

    private func sidebarItem(_ item: SettingsTab) -> some View {
        let selected = tab == item
        return Button {
            tab = item
        } label: {
            HStack(spacing: 9) {
                Image(systemName: item.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? SeenTheme.Paper.accent : SeenTheme.Paper.ink2)
                    .frame(width: 18, alignment: .center)
                Text(item.label)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? SeenTheme.Paper.ink : SeenTheme.Paper.ink2)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(SeenTheme.Paper.surface)
                        .shadow(color: SeenTheme.cardShadow, radius: 1, x: 0, y: 1)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(SeenTheme.Paper.border, lineWidth: 0.5))
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        switch tab {
        case .general:     GeneralPane()
        case .hotkey:      HotkeyPane()
        case .destination: DestinationPane()
        case .permissions: PermissionsPane()
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return "v" + (v ?? "0.1.0")
    }
}

// MARK: - Pane scaffold

private struct Pane<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(SeenTheme.Paper.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(SeenTheme.Paper.mute)
                    }
                }
                content
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FieldRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var isLast: Bool = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        CardRow(isLast: isLast) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SeenTheme.Paper.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(SeenTheme.Paper.mute)
                    }
                }
                Spacer(minLength: 8)
                trailing
            }
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @EnvironmentObject var composition: Composition
    @State private var showImporter = false

    var body: some View {
        @Bindable var settings = composition.settings

        Pane("General", subtitle: "Where screenshots are saved.") {
            SectionLabel(text: "Screenshots folder")
            SettingsCard {
                FieldRow(title: "Save location",
                         subtitle: settings.saveDirectoryPath,
                         isLast: true) {
                    Button("Choose…") { showImporter = true }
                        .buttonStyle(PaperSecondaryButtonStyle())
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder]) { result in
                if let url = try? result.get() { settings.saveDirectoryPath = url.path }
            }

            infoNote("Captures are encoded for Claude's vision automatically — PNG at 1568 px on the longest edge. PNG keeps on-screen text sharp at no extra token cost, and OCR always runs on the full-resolution frame first. Agents can override format (e.g. JPEG for a smaller payload), quality, and size per request via the API.")
        }
    }

    private func infoNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(SeenTheme.Paper.mute)
            Text(text).font(.system(size: 11)).foregroundStyle(SeenTheme.Paper.mute)
        }
    }
}

// MARK: - Hotkey

private struct HotkeyPane: View {
    @EnvironmentObject var composition: Composition
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Pane("Hotkey", subtitle: "Press this shortcut anywhere to capture your screen and push it to your agent.") {
            SectionLabel(text: "Capture & push")
            SettingsCard {
                CardRow(isLast: true) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Global shortcut")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(SeenTheme.Paper.ink)
                            Text(recording ? "Press a key combination…" : "Sends a capture to your configured destination.")
                                .font(.system(size: 11))
                                .foregroundStyle(recording ? SeenTheme.Paper.accent : SeenTheme.Paper.mute)
                        }
                        Spacer(minLength: 8)
                        if recording {
                            Text("Recording…")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(SeenTheme.Paper.accent)
                        } else {
                            KeyChipRow(keyCode: composition.settings.hotkeyCode,
                                       carbonModifiers: composition.settings.hotkeyModifiers)
                        }
                        Button(recording ? "Cancel" : "Record") {
                            recording ? stop() : start()
                        }
                        .buttonStyle(PaperSecondaryButtonStyle())
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(SeenTheme.Paper.mute)
                Text("Use at least one modifier (⌃ ⌥ ⇧ ⌘) so the shortcut doesn't collide with typing.")
                    .font(.system(size: 11))
                    .foregroundStyle(SeenTheme.Paper.mute)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let carbon = Hotkey.carbonModifiers(from: event.modifierFlags)
            // Require a modifier; otherwise ignore and keep listening.
            guard Hotkey.modifierCount(carbon) >= 1 else { return nil }
            composition.settings.hotkeyCode = Int(event.keyCode)
            composition.settings.hotkeyModifiers = carbon
            composition.hotkeyManager.register()
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
}

// MARK: - Destination

private struct DestinationPane: View {
    @EnvironmentObject var composition: Composition

    var body: some View {
        @Bindable var settings = composition.settings

        Pane("Destination", subtitle: "What the hotkey and menu put on your clipboard. Agents pick their own output per request via the API.") {
            SectionLabel(text: "Include")
            SettingsCard {
                CardRow(isLast: true) {
                    Picker("", selection: Binding(
                        get: { settings.captureOutput },
                        set: { settings.captureOutput = $0 })) {
                        Text("Image + text").tag(CaptureRequest.Output.both)
                        Text("Image only").tag(CaptureRequest.Output.image)
                        Text("Text only").tag(CaptureRequest.Output.text)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            infoNote("The hotkey and menu copy the capture's file path — and its OCR text — to the clipboard, so you can paste it into any agent session. Copying spawns nothing under Seen, so a capture never drags a child process's permission prompts onto the app. “Text only” copies just the OCR; the image file is still saved to disk either way.")
        }
    }

    private func infoNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(SeenTheme.Paper.mute)
            Text(text).font(.system(size: 11)).foregroundStyle(SeenTheme.Paper.mute)
        }
    }
}

// MARK: - Permissions

private struct PermissionsPane: View {
    @EnvironmentObject var composition: Composition

    var body: some View {
        Pane("Permissions", subtitle: "Seen needs one permission — Screen Recording — to see anything.") {
            SettingsCard {
                CardRow(isLast: true) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(granted ? SeenTheme.Paper.goodSoft : SeenTheme.Paper.accentSoft)
                                .frame(width: 30, height: 30)
                            Image(systemName: "rectangle.dashed.badge.record")
                                .font(.system(size: 14))
                                .foregroundStyle(granted ? SeenTheme.Paper.good : SeenTheme.Paper.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Screen Recording")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(SeenTheme.Paper.ink)
                                StatusPill(text: "Required", fg: SeenTheme.Paper.bad, bg: SeenTheme.Paper.badSoft)
                            }
                            Text("Lets Seen capture your displays, windows, and apps.")
                                .font(.system(size: 11))
                                .foregroundStyle(SeenTheme.Paper.mute)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            StatusPill(text: granted ? "Granted" : "Not granted",
                                       fg: granted ? SeenTheme.Paper.good : SeenTheme.Paper.bad,
                                       bg: granted ? SeenTheme.Paper.goodSoft : SeenTheme.Paper.badSoft)
                            if !granted {
                                Button("Grant…") {
                                    _ = CGRequestScreenCaptureAccess()
                                    composition.appState.recheckPermission()
                                }
                                .buttonStyle(PaperSecondaryButtonStyle())
                            }
                        }
                    }
                }
            }

            if !granted {
                Button("Open System Settings → Screen Recording") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(PaperSecondaryButtonStyle())
                .fixedSize()
            }
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            composition.appState.recheckPermission()
        }
    }

    private var granted: Bool { composition.appState.hasPermission }
}
