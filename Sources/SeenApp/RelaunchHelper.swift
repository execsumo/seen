import AppKit

enum RelaunchHelper {
    static func relaunch(onFailure: @MainActor @Sendable @escaping () -> Void) {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
            if let error = error {
                print("Relaunch failed: \(error)")
                Task { @MainActor in
                    onFailure()
                }
                return
            }
            
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}
