import SwiftUI
import AppKit
import SeenKit

public struct OnboardingView: View {
    @EnvironmentObject var composition: Composition

    public init() {}

    @State private var didTapRestart = false

    private var phase: PermissionPhase { composition.appState.permissionPhase }
    private var granted: Bool { phase == .granted }

    public var body: some View {
        VStack(spacing: 0) {
            // Paper header
            VStack(spacing: 12) {
                SeenMark(size: 56)
                Text("Seen sees your screen for your agents.")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SeenTheme.Paper.ink)
                    .multilineTextAlignment(.center)
                Text("It needs Screen Recording permission to capture displays, windows, and apps.")
                    .font(.system(size: 12))
                    .foregroundStyle(SeenTheme.Paper.mute)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .padding(.top, 28)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [SeenTheme.Paper.surface, SeenTheme.Paper.sidebar],
                               startPoint: .top, endPoint: .bottom)
            )

            SeenTheme.Paper.border.frame(height: 0.5)

            VStack(spacing: 14) {
                SettingsCard {
                    CardRow(isLast: true) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(granted ? SeenTheme.Paper.goodSoft : SeenTheme.Paper.accentSoft)
                                    .frame(width: 32, height: 32)
                                Image(systemName: granted ? "checkmark" : "rectangle.dashed.badge.record")
                                    .font(.system(size: 15))
                                    .foregroundStyle(granted ? SeenTheme.Paper.good : SeenTheme.Paper.accent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Screen Recording")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(SeenTheme.Paper.ink)
                                Text(granted ? "Granted — you're all set." : "Required to capture your screen.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(SeenTheme.Paper.mute)
                            }
                            Spacer()
                            StatusPill(text: phase == .granted ? "Granted" : (phase == .requestedPendingRestart ? "Restart Needed" : "Needed"),
                                       fg: granted ? SeenTheme.Paper.good : SeenTheme.Paper.bad,
                                       bg: granted ? SeenTheme.Paper.goodSoft : SeenTheme.Paper.badSoft)
                        }
                    }
                }

                if phase == .granted {
                    Text("You can close this window — Seen lives in your menu bar.")
                        .font(.system(size: 11))
                        .foregroundStyle(SeenTheme.Paper.mute)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if phase == .requestedPendingRestart {
                    Text("macOS needs Seen to restart before it can see your screen.")
                        .font(.system(size: 11))
                        .foregroundStyle(SeenTheme.Paper.mute)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text("Seen needs permission to work. You can always change this in System Settings.")
                        .font(.system(size: 11))
                        .foregroundStyle(SeenTheme.Paper.mute)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                
                if !granted {
                    HStack(spacing: 10) {
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(PaperSecondaryButtonStyle())
                        .fixedSize()

                        if phase == .requestedPendingRestart {
                            Button(didTapRestart ? "Restarting…" : "Quit and Reopen Seen") {
                                didTapRestart = true
                                RelaunchHelper.relaunch {
                                    didTapRestart = false
                                }
                            }
                            .buttonStyle(PaperPrimaryButtonStyle())
                            .disabled(didTapRestart)
                        } else {
                            Button("Grant Permission") {
                                _ = CGRequestScreenCaptureAccess()
                                composition.appState.markPermissionRequested()
                            }
                            .buttonStyle(PaperPrimaryButtonStyle())
                        }
                    }
                }
                Spacer()
            }
            .padding(20)
        }
        .frame(width: 420, height: 340)
        .background(SeenTheme.Paper.bg)
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            composition.appState.recheckPermission()
        }
    }
}
