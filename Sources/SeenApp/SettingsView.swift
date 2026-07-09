import SwiftUI
import AppKit
import SeenKit

// MARK: - Settings shell

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, hotkey, destination, agent, permissions
    var id: String { rawValue }

    var label: String {
        switch self {
        case .general:     return "General"
        case .hotkey:      return "Hotkey"
        case .destination: return "Destination"
        case .agent:       return "Agent Access"
        case .permissions: return "Permissions"
        }
    }

    var icon: String {
        switch self {
        case .general:     return "gearshape"
        case .hotkey:      return "keyboard"
        case .destination: return "arrow.up.forward.app"
        case .agent:       return "point.3.connected.trianglepath.dotted"
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
        case .agent:       AgentAccessPane()
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

        Pane("General", subtitle: "Where screenshots are saved and how they're encoded.") {
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

            SectionLabel(text: "Image quality")
            SettingsCard {
                FieldRow(title: "Format",
                         subtitle: "How captures are encoded on disk.") {
                    Picker("", selection: Binding(
                        get: { settings.defaultFormat.rawValue },
                        set: { settings.defaultFormat = ImageFormat(rawValue: $0) ?? .jpeg })) {
                        Text("JPEG").tag("jpeg")
                        Text("HEIC").tag("heic")
                        Text("PNG").tag("png")
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                FieldRow(title: "Quality",
                         subtitle: "Higher looks better but costs more tokens.") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.defaultQuality, in: 0.3...1, step: 0.05)
                            .frame(width: 130)
                        Text("\(Int(settings.defaultQuality * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(SeenTheme.Paper.mute)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
                FieldRow(title: "Max dimension",
                         subtitle: "Longest edge. 1568 px is Claude's vision sweet spot.",
                         isLast: true) {
                    Stepper(value: $settings.defaultMaxDimension, in: 500...4000, step: 100) {
                        Text("\(settings.defaultMaxDimension) px")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(SeenTheme.Paper.ink)
                    }
                    .frame(width: 130)
                }
            }
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

    enum DestType: String, CaseIterable, Identifiable {
        case command = "New agent session"
        case tmux = "Existing tmux session"
        case clipboard = "Clipboard"
        var id: String { rawValue }
    }

    @State private var type: DestType = .command
    @State private var commandText = "claude -p \"look at {path}\""
    @State private var tmuxPane = ""
    @State private var tmuxTemplate = "claude -p \"look at {path}\""
    @State private var tmuxPanes: [String] = []

    var body: some View {
        @Bindable var settings = composition.settings

        Pane("Destination", subtitle: "What the hotkey and menu do with a capture. Agents pick their own output per request.") {
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
            infoNote("“Text only” pushes just the OCR — no screenshot. The image file is still saved to disk either way.")

            SectionLabel(text: "Deliver to")
            SettingsCard {
                CardRow(isLast: true) {
                    Picker("", selection: $type) {
                        ForEach(DestType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: type) { _, _ in save() }
                }
            }

            switch type {
            case .command:
                SectionLabel(text: "Command template")
                SettingsCard {
                    CardRow {
                        HStack {
                            TextField("claude -p \"look at {path}\"", text: $commandText)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .onChange(of: commandText) { _, _ in save() }
                            Menu("Presets") {
                                Button("claude") { commandText = "claude -p \"look at {path}\""; save() }
                                Button("codex")  { commandText = "codex --image {path}"; save() }
                                Button("cline")  { commandText = "cline -p {path}"; save() }
                                Button("agy")    { commandText = "agy --image {path}"; save() }
                            }
                            .frame(width: 90)
                        }
                    }
                    FieldRow(title: "Placeholders",
                             subtitle: "{path}, {paths}, {text} — substituted and shell-escaped.",
                             isLast: true) { EmptyView() }
                }
                infoNote("Runs your command with the capture, starting a new agent session.")

            case .tmux:
                SectionLabel(text: "tmux pane")
                SettingsCard {
                    FieldRow(title: "Target pane") {
                        Picker("", selection: $tmuxPane) {
                            ForEach(tmuxPanes, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        .onChange(of: tmuxPane) { _, _ in save() }
                    }
                    CardRow(isLast: true) {
                        TextField("claude -p \"look at {path}\"", text: $tmuxTemplate)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .onChange(of: tmuxTemplate) { _, _ in save() }
                    }
                }
                infoNote("Types the text into a running tmux pane — drops the capture into an ongoing session.")

            case .clipboard:
                infoNote("Copies the capture's file path and OCR text to the clipboard. Paste it wherever you like.")
            }
        }
        .onAppear(perform: load)
    }

    private func infoNote(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(SeenTheme.Paper.mute)
            Text(text).font(.system(size: 11)).foregroundStyle(SeenTheme.Paper.mute)
        }
    }

    private func load() {
        switch composition.settings.pushDestination {
        case .commandTemplate(let t): type = .command; commandText = t
        case .tmuxPane(let p, let t):  type = .tmux; tmuxPane = p; tmuxTemplate = t
        case .clipboard:               type = .clipboard
        }
        loadPanes()
    }

    private func save() {
        switch type {
        case .command:   composition.settings.pushDestination = .commandTemplate(commandText)
        case .tmux:      composition.settings.pushDestination = .tmuxPane(pane: tmuxPane, template: tmuxTemplate)
        case .clipboard: composition.settings.pushDestination = .clipboard
        }
    }

    private func loadPanes() {
        Task {
            let tmp = "/tmp/seen_tmux_panes"
            _ = try? await composition.pipeline.processRunner.run("/bin/zsh", ["-c", "tmux list-panes -a -F \"#{pane_id} #{pane_title}\" > \(tmp)"])
            if let content = try? String(contentsOfFile: tmp, encoding: .utf8) {
                tmuxPanes = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
                if tmuxPane.isEmpty, let first = tmuxPanes.first { tmuxPane = first }
            }
        }
    }
}

// MARK: - Agent Access

private struct AgentAccessPane: View {
    @EnvironmentObject var composition: Composition
    @State private var copied: String?

    private let socketPath = "~/Library/Application Support/Seen/seen.sock"

    var body: some View {
        Pane("Agent Access", subtitle: "How your CLI agents reach the screen. This is the whole point of Seen.") {
            heroCard

            SectionLabel(text: "Connect an agent")
            SettingsCard {
                copyRow(title: "Claude Code",
                        subtitle: "Register the MCP server once.",
                        value: "claude mcp add seen -- seen mcp")
                copyRow(title: "codex · cline · agy",
                        subtitle: "Add `seen mcp` as a stdio MCP server in the agent's config.",
                        value: "seen mcp")
                copyRow(title: "Install the CLI",
                        subtitle: "Put `seen` on your PATH for shell use.",
                        value: "cp .build/debug/seen /usr/local/bin/",
                        isLast: true)
            }

            SectionLabel(text: "Details")
            SettingsCard {
                copyRow(title: "Socket", subtitle: "Local, 0600 — nothing listens on the network.",
                        value: socketPath)
                copyRow(title: "Raw HTTP",
                        subtitle: "For tools that speak neither MCP nor the CLI.",
                        value: "curl --unix-socket \(socketPath) http://seen/capture",
                        isLast: true)
            }
        }
    }

    private var heroCard: some View {
        HStack(spacing: 12) {
            StatusDot(color: dotColor, pulsing: composition.appState.serverStatus == .starting)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SeenTheme.Paper.heroInk)
                Text(statusSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(SeenTheme.Paper.heroInk.opacity(0.7))
            }
            Spacer()
            Image(systemName: "eye")
                .font(.system(size: 22))
                .foregroundStyle(SeenTheme.Paper.heroInk.opacity(0.35))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SeenTheme.Radius.hero)
                .fill(SeenTheme.Paper.heroBg)
        )
    }

    private var dotColor: Color {
        switch composition.appState.serverStatus {
        case .running:  return SeenTheme.Paper.good
        case .starting: return SeenTheme.Paper.warn
        case .failed:   return SeenTheme.Paper.bad
        }
    }

    private var statusTitle: String {
        switch composition.appState.serverStatus {
        case .running:  return "Agent bridge is running"
        case .starting: return "Starting agent bridge…"
        case .failed:   return "Agent bridge is offline"
        }
    }

    private var statusSubtitle: String {
        switch composition.appState.serverStatus {
        case .running:  return "Registered agents can pull screenshots and OCR on demand."
        case .starting: return "Binding the local socket…"
        case .failed(let msg): return msg
        }
    }

    private func copyRow(title: String, subtitle: String, value: String, isLast: Bool = false) -> some View {
        CardRow(isLast: isLast) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SeenTheme.Paper.ink)
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(SeenTheme.Paper.mute)
                    }
                    Spacer()
                    Button {
                        copy(value)
                    } label: {
                        Label(copied == value ? "Copied" : "Copy",
                              systemImage: copied == value ? "checkmark" : "doc.on.doc")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(PaperSecondaryButtonStyle())
                }
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SeenTheme.Paper.ink2)
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SeenTheme.Paper.surfaceAlt, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func copy(_ value: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
        copied = value
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if copied == value { copied = nil }
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
