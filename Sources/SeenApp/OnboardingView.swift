import SwiftUI
import AppKit
import SeenKit

public struct OnboardingView: View {
    @EnvironmentObject var composition: Composition

    public init() {}

    @State private var didTapRestart = false
    @State private var relaunchFailed = false

    private var phase: PermissionPhase { composition.appState.permissionPhase }
    private var granted: Bool { phase == .granted }

    public var body: some View {
        VStack(spacing: 0) {
            // Hero: flat tonal layer, no gradient, no shadow.
            VStack(spacing: SeenTheme.Spacing.md) {
                SeenMark(size: 56)
                Text("Seen sees your screen for your agents.")
                    .seenType(SeenType.bodyMD.weighted(.semibold))
                    .foregroundStyle(SeenTheme.Term.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("It needs Screen Recording permission to capture displays, windows, and apps.")
                    .seenType(SeenType.caption)
                    .foregroundStyle(SeenTheme.Term.mute)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, SeenTheme.Spacing.xl)
            .padding(.horizontal, SeenTheme.Spacing.lg)
            .padding(.bottom, SeenTheme.Spacing.lg)
            .frame(maxWidth: .infinity)
            .background(SeenTheme.Term.elevated)

            HRule()

            VStack(spacing: SeenTheme.Spacing.md) {
                SettingsCard {
                    CardRow(isLast: true) {
                        HStack(spacing: SeenTheme.Spacing.md) {
                            ZStack {
                                Rectangle()
                                    .fill((granted ? SeenTheme.Term.good : SeenTheme.Term.amber).opacity(0.12))
                                    .frame(width: 32, height: 32)
                                    .terminalBorder((granted ? SeenTheme.Term.good : SeenTheme.Term.amber).opacity(0.45))
                                Image(systemName: granted ? "checkmark" : "rectangle.dashed.badge.record")
                                    .font(.system(size: 15))
                                    .foregroundStyle(granted ? SeenTheme.Term.good : SeenTheme.Term.amber)
                            }
                            VStack(alignment: .leading, spacing: SeenTheme.Spacing.hair) {
                                Text("Screen Recording")
                                    .seenType(SeenType.bodySM.weighted(.medium))
                                    .foregroundStyle(SeenTheme.Term.ink)
                                Text(granted ? "Granted — you're all set." : "Required to capture your screen.")
                                    .seenType(SeenType.caption)
                                    .foregroundStyle(SeenTheme.Term.mute)
                            }
                            Spacer(minLength: SeenTheme.Spacing.sm)
                            StatusTag(text: phase == .granted ? "Granted" : (phase == .requestedPendingRestart ? "Restart needed" : "Needed"),
                                      color: granted ? SeenTheme.Term.good : SeenTheme.Term.bad)
                        }
                    }
                }

                if phase == .granted {
                    note("You can close this window — Seen lives in your menu bar.")
                } else if phase == .requestedPendingRestart {
                    note("If you've already allowed Seen in System Settings, it needs to restart before it can see your screen.")
                } else {
                    note("Seen needs permission to work. You can always change this in System Settings.")
                }

                if !granted {
                    HStack(spacing: SeenTheme.Spacing.md) {
                        Button("Open System Settings") {
                            composition.appState.markPermissionRequested()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(TerminalSecondaryButtonStyle())
                        .fixedSize()

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
                            Button("Grant Permission") {
                                _ = CGRequestScreenCaptureAccess()
                                composition.appState.markPermissionRequested()
                            }
                            .buttonStyle(TerminalPrimaryButtonStyle(fillWidth: false))
                        }
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
                Spacer()
            }
            .padding(SeenTheme.Spacing.lg)
        }
        .frame(width: 460, height: 440)
        .background(SeenTheme.Term.base)
        .preferredColorScheme(.dark)
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            composition.appState.recheckPermission()
        }
    }

    private func note(_ text: String) -> some View {
        HStack(alignment: .top, spacing: SeenTheme.Spacing.sm) {
            Marker(color: SeenTheme.Term.dim)
            Text(text)
                .seenType(SeenType.caption)
                .foregroundStyle(SeenTheme.Term.mute)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
