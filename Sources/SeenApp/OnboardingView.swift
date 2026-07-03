import SwiftUI
import AppKit

public struct OnboardingView: View {
    @EnvironmentObject var composition: Composition
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to Seen")
                .font(.largeTitle)
            Text("Seen needs Screen Recording permission to capture your screen.")
            
            HStack {
                Circle()
                    .fill(composition.appState.hasPermission ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(composition.appState.hasPermission ? "Permission Granted" : "Permission Required")
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
            
            if composition.appState.hasPermission {
                Text("You can now close this window.")
            }
        }
        .padding()
        .frame(width: 400, height: 300)
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            composition.appState.recheckPermission()
        }
    }
}
