import SwiftUI
import AppKit
import SeenKit

public struct SettingsView: View {
    @EnvironmentObject var composition: Composition
    
    public init() {}
    
    public var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            
            HotkeySettingsView()
                .tabItem { Label("Hotkey", systemImage: "keyboard") }
            
            DestinationSettingsView()
                .tabItem { Label("Destination", systemImage: "arrow.up.forward.app") }
            
            APISettingsView()
                .tabItem { Label("API", systemImage: "network") }
            
            PermissionsSettingsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var composition: Composition
    @State private var showFileImporter = false
    
    var body: some View {
        @Bindable var settings = composition.settings
        
        Form {
            Section(header: Text("Save Directory")) {
                HStack {
                    Text(settings.saveDirectoryPath)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose...") { showFileImporter = true }
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                if let url = try? result.get().first {
                    settings.saveDirectoryPath = url.path
                }
            }
            
            Section(header: Text("Image Quality")) {
                Picker("Format", selection: Binding(
                    get: { settings.defaultFormat.rawValue },
                    set: { settings.defaultFormat = ImageFormat(rawValue: $0) ?? .jpeg }
                )) {
                    Text("JPEG").tag("jpeg")
                    Text("HEIC").tag("heic")
                    Text("PNG").tag("png")
                }
                
                Slider(value: $settings.defaultQuality, in: 0...1, step: 0.05) {
                    Text("Quality")
                }
                
                Stepper(value: $settings.defaultMaxDimension, in: 500...4000, step: 100) {
                    Text("Max Dimension: \(settings.defaultMaxDimension) px")
                }
            }
        }
        .padding()
    }
}

struct HotkeySettingsView: View {
    @EnvironmentObject var composition: Composition
    @State private var isRecording = false
    @State private var monitor: Any?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Global Hotkey")
                .font(.headline)
            
            HStack {
                Text(isRecording ? "Press any key combination..." : "Code: \(composition.settings.hotkeyCode), Modifiers: \(composition.settings.hotkeyModifiers)")
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                
                Button(isRecording ? "Cancel" : "Record Shortcut") {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }
            }
        }
        .onDisappear { stopRecording() }
    }
    
    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            composition.settings.hotkeyCode = Int(event.keyCode)
            composition.settings.hotkeyModifiers = Int(event.modifierFlags.rawValue)
            composition.hotkeyManager.register()
            stopRecording()
            return nil
        }
    }
    
    private func stopRecording() {
        isRecording = false
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

struct DestinationSettingsView: View {
    @EnvironmentObject var composition: Composition
    
    enum DestType: String, CaseIterable {
        case command = "Command Template"
        case tmux = "tmux Pane"
        case clipboard = "Clipboard"
    }
    
    @State private var selectedType: DestType = .command
    @State private var commandText: String = "claude -p \"look at {path}\""
    @State private var selectedTmuxPane: String = ""
    @State private var tmuxTemplate: String = "claude -p \"look at {path}\""
    @State private var tmuxPanes: [String] = []
    
    var body: some View {
        Form {
            Picker("Type", selection: $selectedType) {
                ForEach(DestType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .onChange(of: selectedType) { updateSettings() }
            
            if selectedType == .command {
                TextField("Command", text: $commandText)
                    .onChange(of: commandText) { updateSettings() }
                
                Menu("Presets") {
                    Button("claude") { commandText = "claude -p \"look at {path}\"" }
                    Button("codex") { commandText = "codex --image {path}" }
                    Button("cline") { commandText = "cline -p {path}" }
                    Button("agy") { commandText = "agy --image {path}" }
                }
            } else if selectedType == .tmux {
                Picker("Pane", selection: $selectedTmuxPane) {
                    ForEach(tmuxPanes, id: \.self) { pane in
                        Text(pane).tag(pane)
                    }
                }
                .onChange(of: selectedTmuxPane) { updateSettings() }
                .onAppear { loadTmuxPanes() }
                
                TextField("Template", text: $tmuxTemplate)
                    .onChange(of: tmuxTemplate) { updateSettings() }
            }
        }
        .padding()
        .onAppear {
            switch composition.settings.pushDestination {
            case .commandTemplate(let text):
                selectedType = .command
                commandText = text
            case .tmuxPane(let pane, let template):
                selectedType = .tmux
                selectedTmuxPane = pane
                tmuxTemplate = template
            case .clipboard:
                selectedType = .clipboard
            }
        }
    }
    
    private func updateSettings() {
        switch selectedType {
        case .command:
            composition.settings.pushDestination = .commandTemplate(commandText)
        case .tmux:
            composition.settings.pushDestination = .tmuxPane(pane: selectedTmuxPane, template: tmuxTemplate)
        case .clipboard:
            composition.settings.pushDestination = .clipboard
        }
    }
    
    private func loadTmuxPanes() {
        Task {
            do {
                let tempPath = "/tmp/seen_tmux_panes"
                _ = try await composition.pipeline.processRunner.run("/bin/zsh", ["-c", "tmux list-panes -a -F \"#{pane_id} #{pane_title}\" > \(tempPath)"])
                if let content = try? String(contentsOfFile: tempPath, encoding: .utf8) {
                    self.tmuxPanes = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    if selectedTmuxPane.isEmpty && !self.tmuxPanes.isEmpty {
                        selectedTmuxPane = self.tmuxPanes[0]
                    }
                }
            } catch {
                print("Failed to load tmux panes: \(error)")
            }
        }
    }
}

struct APISettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("API Status")
                .font(.headline)
            Text("Unix Socket: ~/Library/Application Support/Seen/seen.sock")
            Button("Copy curl example") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString("curl --unix-socket ~/Library/Application\\ Support/Seen/seen.sock http://seen/capture", forType: .string)
            }
        }
        .padding()
    }
}

struct PermissionsSettingsView: View {
    @EnvironmentObject var composition: Composition
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Circle()
                    .fill(composition.appState.hasPermission ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(composition.appState.hasPermission ? "Screen Recording: Granted" : "Screen Recording: Required")
            }
            
            Button("Request Permission") {
                _ = CGRequestScreenCaptureAccess()
                composition.appState.recheckPermission()
            }
            
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding()
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            composition.appState.recheckPermission()
        }
    }
}
