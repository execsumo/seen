// Renders a proof sheet of the real design system to a PNG, headlessly.
//
// This is not a mock: it is compiled together with the shipping
// Sources/SeenApp/DesignSystem.swift, so every swatch, type step, and component
// below is the same code the app runs. It uses ImageRenderer, so it needs no
// window, no click, and no Accessibility permission — the one thing it cannot
// cover is how the real MenuContent/SettingsView/OnboardingView compose these
// pieces, which is a human click-through.
//
//   swiftc -O scripts/DesignProof.swift Sources/SeenApp/DesignSystem.swift -o /tmp/designproof
//   mkdir -p /tmp/Fonts && cp Sources/SeenApp/Resources/Fonts/*.ttf /tmp/Fonts/
//   cp /tmp/designproof /tmp/ && cd /tmp && ./designproof proof.png
//
// The Fonts/ directory must sit next to the binary: that is one of the roots
// SeenFonts.bundledFontURLs() searches, so this exercises the app's real font
// discovery rather than registering the faces behind its back.

import SwiftUI
import AppKit
import Carbon

@main
struct DesignProof {
    @MainActor
    static func main() {
        // Touch NSApplication so AppKit's font and graphics stacks are live in a
        // plain CLI process, but stay out of the Dock.
        NSApplication.shared.setActivationPolicy(.accessory)

        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "proof.png"

        print("JetBrains Mono resolved: \(SeenFonts.isAvailable)")
        if !SeenFonts.isAvailable {
            print("WARNING: the sheet below is rendering in the system monospace fallback,")
            print("         not JetBrains Mono. Check that Fonts/ sits next to this binary.")
        }

        let renderer = ImageRenderer(content: ProofSheet())
        renderer.scale = 2

        guard let cg = renderer.cgImage else {
            print("FAIL: ImageRenderer produced no image"); exit(1)
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            print("FAIL: could not encode PNG"); exit(1)
        }
        do {
            try data.write(to: URL(fileURLWithPath: out))
            print("wrote \(out) — \(cg.width)x\(cg.height)px")
            exit(0)
        } catch {
            print("FAIL: \(error)"); exit(1)
        }
    }
}

// MARK: - The sheet

struct ProofSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SeenTheme.Spacing.lg) {
            header
            palette
            typeScale
            components
        }
        .padding(SeenTheme.Spacing.xl)
        .frame(width: 980, alignment: .leading)
        .background(SeenTheme.Term.base)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: SeenTheme.Spacing.md) {
            SeenMark(size: 48)
            VStack(alignment: .leading, spacing: SeenTheme.Spacing.hair) {
                Text("SEEN — DESIGN PROOF")
                    .seenType(SeenType.headlineMD)
                    .foregroundStyle(SeenTheme.Term.ink)
                Text("Rendered from Sources/SeenApp/DesignSystem.swift")
                    .seenType(SeenType.caption)
                    .foregroundStyle(SeenTheme.Term.mute)
            }
            Spacer()
            StatusTag(text: SeenFonts.isAvailable ? "JetBrains Mono" : "FALLBACK FACE",
                      color: SeenFonts.isAvailable ? SeenTheme.Term.good : SeenTheme.Term.bad)
        }
    }

    // MARK: Palette

    private let swatches: [(String, String, Color)] = [
        ("base", "08080B", SeenTheme.Term.base),
        ("sunken", "0E0E11", SeenTheme.Term.sunken),
        ("elevated", "121217", SeenTheme.Term.elevated),
        ("raised", "1B1B1F", SeenTheme.Term.raised),
        ("high", "201F23", SeenTheme.Term.high),
        ("border", "1C1C22", SeenTheme.Term.border),
        ("borderStrong", "524439", SeenTheme.Term.borderStrong),
        ("ink", "E5E1E6", SeenTheme.Term.ink),
        ("body", "D7C3B4", SeenTheme.Term.body),
        ("mute", "C0B7A9", SeenTheme.Term.mute),
        ("dim", "9F8D80", SeenTheme.Term.dim),
        ("amber", "FFB46E", SeenTheme.Term.amber),
        ("amberBright", "FFB876", SeenTheme.Term.amberBright),
        ("amberSoft", "FFD9BA", SeenTheme.Term.amberSoft),
        ("onAmber", "4B2800", SeenTheme.Term.onAmber),
        ("green", "A6E22E", SeenTheme.Term.green),
        ("blue", "66D9EF", SeenTheme.Term.blue),
        ("cyan", "AAEAFF", SeenTheme.Term.cyan),
        ("error", "FFB4AB", SeenTheme.Term.error),
    ]

    private var palette: some View {
        VStack(alignment: .leading, spacing: SeenTheme.Spacing.sm) {
            SectionLabel(text: "Palette — every value traced to DESIGN.md")
            // Eager stacks, not LazyVGrid: lazy containers can rasterise empty
            // under ImageRenderer because nothing ever scrolls them into view.
            VStack(alignment: .leading, spacing: SeenTheme.Spacing.sm) {
                ForEach(Array(stride(from: 0, to: swatches.count, by: 5)), id: \.self) { start in
                    HStack(alignment: .top, spacing: SeenTheme.Spacing.sm) {
                        ForEach(start..<min(start + 5, swatches.count), id: \.self) { i in
                            let sw = swatches[i]
                            VStack(alignment: .leading, spacing: 0) {
                                sw.2.frame(height: 44).terminalBorder()
                                Text(sw.0)
                                    .seenType(SeenType.caption)
                                    .foregroundStyle(SeenTheme.Term.body)
                                    .padding(.top, SeenTheme.Spacing.hair)
                                Text("#\(sw.1)")
                                    .seenType(SeenType.caption)
                                    .foregroundStyle(SeenTheme.Term.dim)
                            }
                            .frame(width: 168, alignment: .leading)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: Type

    private var typeScale: some View {
        VStack(alignment: .leading, spacing: SeenTheme.Spacing.sm) {
            SectionLabel(text: "Type — JetBrains Mono, the spec's named steps")
            SettingsCard {
                typeRow("headline-lg-mobile 24/600", SeenType.headlineMD, "Permissions")
                typeRow("body-md 16/400", SeenType.bodyMD, "Seen sees your screen.")
                typeRow("body-sm 14/400", SeenType.bodySM, "Open Screenshots Folder")
                typeRow("label-md 12/500 +0.05em", SeenType.label, "CAPTURE & PUSH")
                typeRow("code-block 14/400", SeenType.code, "il1 O0 {} <=> ~ /Users/you/Seen")
                typeRow("caption 12/400", SeenType.caption, "Agents can see your screen",
                        isLast: true)
            }
        }
    }

    private func typeRow(_ label: String, _ style: SeenType.Style,
                         _ sample: String, isLast: Bool = false) -> some View {
        CardRow(isLast: isLast) {
            HStack(alignment: .firstTextBaseline, spacing: SeenTheme.Spacing.md) {
                Text(label)
                    .seenType(SeenType.caption)
                    .foregroundStyle(SeenTheme.Term.dim)
                    .frame(width: 220, alignment: .leading)
                Text(sample)
                    .seenType(style)
                    .foregroundStyle(SeenTheme.Term.ink)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Components

    private var components: some View {
        VStack(alignment: .leading, spacing: SeenTheme.Spacing.sm) {
            SectionLabel(text: "Components — sharp, 1px borders, tonal depth, no shadows")

            HStack(alignment: .top, spacing: SeenTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: SeenTheme.Spacing.md) {
                    StatusHeaderCard(dotColor: SeenTheme.Term.good, pulsing: false,
                                     title: "Agent Bridge Running",
                                     subtitle: "Agents can see your screen")
                    StatusHeaderCard(dotColor: SeenTheme.Term.bad, pulsing: true,
                                     title: "Capturing on a schedule",
                                     subtitle: "2 active sessions")
                    SettingsCard(title: "Screenshots folder") {
                        CardRow {
                            HStack {
                                Text("Save location")
                                    .seenType(SeenType.bodySM.weighted(.medium))
                                    .foregroundStyle(SeenTheme.Term.ink)
                                Spacer()
                                Button("Choose…") {}
                                    .buttonStyle(TerminalSecondaryButtonStyle())
                            }
                        }
                        CardRow(isLast: true) {
                            CommandLineText(text: "/Users/you/Pictures/Seen")
                        }
                    }
                    InfoNote(text: "Captures are encoded for Claude's vision automatically — PNG at 1568 px on the longest edge.")
                }
                .frame(width: 440)

                VStack(alignment: .leading, spacing: SeenTheme.Spacing.md) {
                    HStack(spacing: SeenTheme.Spacing.sm) {
                        StatusTag(text: "Granted", color: SeenTheme.Term.good)
                        StatusTag(text: "Restart needed", color: SeenTheme.Term.bad)
                        StatusTag(text: "Starting", color: SeenTheme.Term.warn)
                    }
                    HStack(spacing: SeenTheme.Spacing.md) {
                        StatusDot(color: SeenTheme.Term.good, pulsing: false)
                        KeyChipRow(keyCode: 1, carbonModifiers: cmdKey | optionKey | shiftKey)
                        BlockCursor()
                    }
                    HStack(spacing: SeenTheme.Spacing.md) {
                        Button("Grant Permission") {}
                            .buttonStyle(TerminalPrimaryButtonStyle(fillWidth: false))
                        Button("Open System Settings") {}
                            .buttonStyle(TerminalSecondaryButtonStyle())
                    }
                    TerminalSegmented(
                        options: [(label: "Image + text", value: "both"),
                                  (label: "Image only", value: "image"),
                                  (label: "Text only", value: "text")],
                        selection: .constant("both")
                    )
                    SettingsCard(title: "Menu rows") {
                        CardRow {
                            MenuBarRowLabel(title: "Capture Now", icon: "camera.viewfinder",
                                            hotkey: "⌃⌥⌘S")
                        }
                        CardRow {
                            MenuBarRowLabel(title: "Open Screenshots Folder", icon: "folder")
                        }
                        CardRow(isLast: true) {
                            MenuBarRowLabel(title: "Stop session A1B2", icon: "stop.circle",
                                            accent: true)
                        }
                    }
                    HStack(spacing: SeenTheme.Spacing.md) {
                        SeenMark(size: 16)
                        SeenMark(size: 28)
                        SeenMark(size: 56)
                        Spacer()
                    }
                }
                .frame(width: 440)
            }
        }
    }
}
