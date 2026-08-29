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
        .frame(width: 720, height: 540)
        .background(SeenTheme.Term.base)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: SeenTheme.Spacing.sm + 2) {
                SeenMark(size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SEEN")
                        .seenType(SeenType.bodyMD.weighted(.bold))
                        .tracking(1.2)
                        .foregroundStyle(SeenTheme.Term.ink)
                    Text(appVersion)
                        .seenType(SeenType.caption)
                        .foregroundStyle(SeenTheme.Term.dim)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SeenTheme.Spacing.md)
            .padding(.vertical, SeenTheme.Spacing.md)

            HRule()

            VStack(spacing: 0) {
                ForEach(SettingsTab.allCases) { item in
                    sidebarItem(item)
                }
            }
            .padding(.top, SeenTheme.Spacing.sm)

            Spacer()
        }
        .frame(width: 200)
        .background(SeenTheme.Term.elevated)
        .overlay(alignment: .trailing) { SeenTheme.Term.border.frame(width: SeenTheme.hairline) }
    }

    private func sidebarItem(_ item: SettingsTab) -> some View {
        let selected = tab == item
        return Button {
            tab = item
        } label: {
            HStack(spacing: SeenTheme.Spacing.sm) {
                Image(systemName: item.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? SeenTheme.Term.amber : SeenTheme.Term.mute)
                    .frame(width: 16, alignment: .center)
                Text(item.label)
                    .seenType(SeenType.bodySM.weighted(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? SeenTheme.Term.ink : SeenTheme.Term.body)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SeenTheme.Spacing.md)
            .padding(.vertical, SeenTheme.Spacing.sm + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? SeenTheme.Term.raised : Color.clear)
            // Selection is marked with a structural amber rule, not a fill shape.
            .overlay(alignment: .leading) {
                SeenTheme.Term.amber
                    .frame(width: 2)
                    .opacity(selected ? 1 : 0)
            }
            .contentShape(Rectangle())
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
            VStack(alignment: .leading, spacing: SeenTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: SeenTheme.Spacing.sm) {
                    Text(title)
                        .seenType(SeenType.headlineMD)
                        .foregroundStyle(SeenTheme.Term.ink)
                    if let subtitle {
                        Text(subtitle)
                            .seenType(SeenType.caption)
                            .foregroundStyle(SeenTheme.Term.mute)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, SeenTheme.Spacing.sm)

                content
            }
            .padding(SeenTheme.Spacing.lg)
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
            HStack(spacing: SeenTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: SeenTheme.Spacing.hair) {
                    Text(title)
                        .seenType(SeenType.bodySM.weighted(.medium))
                        .foregroundStyle(SeenTheme.Term.ink)
                    if let subtitle {
                        Text(subtitle)
                            .seenType(SeenType.caption)
                            .foregroundStyle(SeenTheme.Term.mute)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: SeenTheme.Spacing.sm)
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
            SettingsCard(title: "Screenshots folder") {
                FieldRow(title: "Save location",
                         subtitle: "Every capture lands here, named by timestamp.") {
                    Button("Choose…") { showImporter = true }
                        .buttonStyle(TerminalSecondaryButtonStyle())
                }
                CardRow(isLast: true) {
                    CommandLineText(text: settings.saveDirectoryPath)
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder]) { result in
                if let url = try? result.get() { settings.saveDirectoryPath = url.path }
            }

            InfoNote(text: "Captures are encoded for Claude's vision automatically — PNG at 1568 px on the longest edge. PNG keeps on-screen text sharp at no extra token cost, and OCR always runs on the full-resolution frame first. Agents can override format (e.g. JPEG for a smaller payload), quality, and size per request via the API.")
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
            SettingsCard(title: "Capture & push") {
                CardRow(isLast: true) {
                    HStack(spacing: SeenTheme.Spacing.md) {
                        VStack(alignment: .leading, spacing: SeenTheme.Spacing.hair) {
                            Text("Global shortcut")
                                .seenType(SeenType.bodySM.weighted(.medium))
                                .foregroundStyle(SeenTheme.Term.ink)
                            Text(recording ? "Press a key combination…" : "Sends a capture to your configured destination.")
                                .seenType(SeenType.caption)
                                .foregroundStyle(recording ? SeenTheme.Term.amber : SeenTheme.Term.mute)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: SeenTheme.Spacing.sm)
                        if recording {
                            // The command-line focus metaphor: a blinking block
                            // cursor waiting on input.
                            BlockCursor()
                        } else {
                            KeyChipRow(keyCode: composition.settings.hotkeyCode,
                                       carbonModifiers: composition.settings.hotkeyModifiers)
                        }
                        Button(recording ? "Cancel" : "Record") {
                            recording ? stop() : start()
                        }
                        .buttonStyle(TerminalSecondaryButtonStyle())
                    }
                }
            }

            InfoNote(text: "Use at least one modifier (⌃ ⌥ ⇧ ⌘) so the shortcut doesn't collide with typing.")
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
            SettingsCard(title: "Include") {
                CardRow(isLast: true) {
                    TerminalSegmented(
                        options: [
                            (label: "Image + text", value: CaptureRequest.Output.both),
                            (label: "Image only",   value: CaptureRequest.Output.image),
                            (label: "Text only",    value: CaptureRequest.Output.text),
                        ],
                        selection: Binding(
                            get: { settings.captureOutput },
                            set: { settings.captureOutput = $0 }
                        )
                    )
                }
            }

            InfoNote(text: "The hotkey and menu copy the capture's file path — and its OCR text — to the clipboard, so you can paste it into any agent session. Copying spawns nothing under Seen, so a capture never drags a child process's permission prompts onto the app. “Text only” copies just the OCR; the image file is still saved to disk either way.")
        }
    }
}

// MARK: - Permissions

private struct PermissionsPane: View {
    @EnvironmentObject var composition: Composition
    @State private var didTapRestart = false
    @State private var relaunchFailed = false

    private var phase: PermissionPhase { composition.appState.permissionPhase }
    private var granted: Bool { phase == .granted }

    var body: some View {
        Pane("Permissions", subtitle: "Seen needs one permission — Screen Recording — to see anything.") {
            SettingsCard(title: "Required") {
                CardRow(isLast: true) {
                    HStack(alignment: .top, spacing: SeenTheme.Spacing.md) {
                        ZStack {
                            Rectangle()
                                .fill(granted ? SeenTheme.Term.good.opacity(0.12)
                                              : SeenTheme.Term.amber.opacity(0.12))
                                .frame(width: 32, height: 32)
                                .terminalBorder((granted ? SeenTheme.Term.good : SeenTheme.Term.amber).opacity(0.45))
                            Image(systemName: "rectangle.dashed.badge.record")
                                .font(.system(size: 14))
                                .foregroundStyle(granted ? SeenTheme.Term.good : SeenTheme.Term.amber)
                        }
                        VStack(alignment: .leading, spacing: SeenTheme.Spacing.hair) {
                            Text("Screen Recording")
                                .seenType(SeenType.bodySM.weighted(.medium))
                                .foregroundStyle(SeenTheme.Term.ink)
                            Text("Lets Seen capture your displays, windows, and apps.")
                                .seenType(SeenType.caption)
                                .foregroundStyle(SeenTheme.Term.mute)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: SeenTheme.Spacing.sm)
                        VStack(alignment: .trailing, spacing: SeenTheme.Spacing.sm) {
                            StatusTag(text: phase == .granted ? "Granted" : (phase == .requestedPendingRestart ? "Restart needed" : "Not granted"),
                                      color: granted ? SeenTheme.Term.good : SeenTheme.Term.bad)
                            if !granted {
                                if phase == .requestedPendingRestart {
                                    Button(didTapRestart ? "Restarting…" : "Quit and Reopen Seen") {
                                        didTapRestart = true
                                        relaunchFailed = false
                                        RelaunchHelper.relaunch {
                                            didTapRestart = false
                                            relaunchFailed = true
                                        }
                                    }
                                    .buttonStyle(TerminalPrimaryButtonStyle(fillWidth: false))
                                    .disabled(didTapRestart)
                                } else {
                                    Button("Grant…") {
                                        _ = CGRequestScreenCaptureAccess()
                                        composition.appState.markPermissionRequested()
                                    }
                                    .buttonStyle(TerminalSecondaryButtonStyle())
                                }
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }

            if !granted {
                Button("Open System Settings → Screen Recording") {
                    composition.appState.markPermissionRequested()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(TerminalSecondaryButtonStyle())
                .fixedSize()

                if phase == .requestedPendingRestart {
                    InfoNote(text: "If you've already allowed Seen in System Settings, it needs to restart before it can see your screen.")
                }

                if relaunchFailed {
                    HStack(alignment: .top, spacing: SeenTheme.Spacing.sm) {
                        Marker(glyph: "!", color: SeenTheme.Term.bad)
                        Text("Couldn't restart automatically — please quit Seen and open it again.")
                            .seenType(SeenType.caption)
                            .foregroundStyle(SeenTheme.Term.bad)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            composition.appState.recheckPermission()
        }
    }
}
