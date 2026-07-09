import SwiftUI
import AppKit
import Carbon

// MARK: - Color helpers

extension Color {
    init(hex: String) {
        let v = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var n: UInt64 = 0
        Scanner(string: v).scanHexInt64(&n)
        self.init(
            red:   Double((n >> 16) & 0xFF) / 255,
            green: Double((n >>  8) & 0xFF) / 255,
            blue:  Double( n        & 0xFF) / 255
        )
    }

    /// A color that resolves differently in light vs dark appearance.
    init(light: String, dark: String) {
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(Color(hex: dark))
            } else {
                return NSColor(Color(hex: light))
            }
        }))
    }
}

// MARK: - Theme ("Paper" palette, shared with Heard)

enum SeenTheme {
    enum Paper {
        static let bg           = Color(light: "F5EFE4", dark: "1C2024")
        static let surface      = Color(light: "FBF7EF", dark: "252A30")
        static let surfaceAlt   = Color(light: "EFE7D7", dark: "2E3338")
        static let sidebar      = Color(light: "EBE2CE", dark: "22272D")
        static let border       = Color(light: "D9CFB9", dark: "4A515A")
        static let borderSoft   = Color(light: "E5DCC8", dark: "3A3F47")
        static let ink          = Color(light: "1C2024", dark: "F5EFE4")
        static let ink2         = Color(light: "3A3F47", dark: "D9CFB9")
        static let mute         = Color(light: "7B7264", dark: "9A9184")
        static let muteSoft     = Color(light: "C9BBA5", dark: "4A515A")
        static let accent       = Color(light: "3F5C8C", dark: "658BC9")
        static let accentInk    = Color(light: "2F4570", dark: "8BB2F2")
        static let accentSoft   = Color(light: "E5EAF3", dark: "26334A")
        static let good         = Color(light: "3D7A4F", dark: "53A66B")
        static let goodSoft     = Color(light: "E1EEDF", dark: "243D2D")
        static let warn         = Color(light: "A66A1F", dark: "D98A29")
        static let warnSoft     = Color(light: "F4E6CE", dark: "4D351A")
        static let bad          = Color(light: "A6452B", dark: "D65738")
        static let badSoft      = Color(light: "F2DCD2", dark: "4A251C")
        static let heroBg       = Color(light: "2E3338", dark: "12161A")
        static let heroInk      = Color(light: "F5EFE4", dark: "F5EFE4")
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
    }

    enum Radius {
        static let inline: CGFloat = 6
        static let card: CGFloat = 10
        static let hero: CGFloat = 14
    }

    /// Warm paper shadow used under cards.
    static let cardShadow = Color(red: 60/255, green: 45/255, blue: 20/255).opacity(0.06)
}

// MARK: - SeenMark (app glyph — an eye, the "vision bridge")

struct SeenMark: View {
    var size: CGFloat = 26

    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 64
            // Squircle background gradient
            let bgPath = RoundedRectangle(cornerRadius: 14 * s)
                .path(in: CGRect(origin: .zero, size: sz))
            ctx.fill(bgPath, with: .linearGradient(
                Gradient(colors: [Color(hex: "E8DFD2"), Color(hex: "C9BBA5")]),
                startPoint: CGPoint(x: sz.width / 2, y: 0),
                endPoint: CGPoint(x: sz.width / 2, y: sz.height)
            ))
            // Eye almond
            var eye = Path()
            eye.move(to: CGPoint(x: 12 * s, y: 32 * s))
            eye.addQuadCurve(to: CGPoint(x: 52 * s, y: 32 * s),
                             control: CGPoint(x: 32 * s, y: 15 * s))
            eye.addQuadCurve(to: CGPoint(x: 12 * s, y: 32 * s),
                             control: CGPoint(x: 32 * s, y: 49 * s))
            eye.closeSubpath()
            ctx.fill(eye, with: .linearGradient(
                Gradient(colors: [Color(hex: "2E3338"), Color(hex: "1C2024")]),
                startPoint: CGPoint(x: sz.width / 2, y: 0),
                endPoint: CGPoint(x: sz.width / 2, y: sz.height)
            ))
            // Iris + pupil
            ctx.fill(
                Path(ellipseIn: CGRect(x: (32 - 9) * s, y: (32 - 9) * s, width: 18 * s, height: 18 * s)),
                with: .color(Color(hex: "E8DFD2"))
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: (32 - 4.5) * s, y: (32 - 4.5) * s, width: 9 * s, height: 9 * s)),
                with: .color(Color(hex: "1C2024"))
            )
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Shared components

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .kerning(0.7)
            .foregroundStyle(SeenTheme.Paper.mute)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeenTheme.Paper.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeenTheme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: SeenTheme.Radius.card)
                .stroke(SeenTheme.Paper.border, lineWidth: 0.5)
        )
        .shadow(color: SeenTheme.cardShadow, radius: 1, x: 0, y: 1)
    }
}

struct CardRow<Content: View>: View {
    var isLast: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            if !isLast {
                SeenTheme.Paper.borderSoft
                    .frame(height: 0.5)
                    .padding(.leading, 12)
            }
        }
    }
}

struct StatusPill: View {
    let text: String
    let fg: Color
    let bg: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(bg, in: Capsule())
    }
}

struct StatusDot: View {
    let color: Color
    let pulsing: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            if pulsing {
                Circle()
                    .fill(color.opacity(pulse ? 0.22 : 0))
                    .frame(width: 14, height: 14)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            }
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .frame(width: 14, height: 14)
        .onAppear { if pulsing { pulse = true } }
    }
}

// MARK: - Key chip (renders a single glyph like ⌘ or S)

struct KeyChip: View {
    let symbol: String
    var body: some View {
        Text(symbol)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(SeenTheme.Paper.ink)
            .frame(minWidth: 24, minHeight: 26)
            .padding(.horizontal, 6)
            .background(SeenTheme.Paper.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(SeenTheme.Paper.border, lineWidth: 0.5)
            )
            .shadow(color: SeenTheme.cardShadow, radius: 0.5, x: 0, y: 1)
    }
}

/// Renders a hotkey as a row of key chips (⌃ ⌥ ⌘ S).
struct KeyChipRow: View {
    let keyCode: Int
    let carbonModifiers: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Hotkey.symbols(keyCode: keyCode, carbonModifiers: carbonModifiers), id: \.self) { sym in
                KeyChip(symbol: sym)
            }
        }
    }
}

// MARK: - Menu-bar panel components

struct StatusHeaderCard: View {
    let dotColor: Color
    let pulsing: Bool
    let title: String
    let subtitle: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(color: dotColor, pulsing: pulsing)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SeenTheme.Paper.ink)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(SeenTheme.Paper.mute)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            if let trailing { trailing }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SeenTheme.Radius.card)
                .fill(SeenTheme.Paper.surfaceAlt)
        )
    }
}

struct MenuBarRow: View {
    let title: String
    let icon: String
    var accent: Bool = false
    var hotkey: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(accent ? SeenTheme.Paper.accent : SeenTheme.Paper.ink2)
                    .frame(width: 18, alignment: .center)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accent ? SeenTheme.Paper.accent : SeenTheme.Paper.ink)
                Spacer()
                if let hotkey {
                    Text(hotkey)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SeenTheme.Paper.mute)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .buttonStyle(MenuBarRowStyle())
    }
}

struct MenuBarRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? SeenTheme.Paper.surfaceAlt : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
    }
}

// MARK: - Paper button styles

/// Filled accent button (primary action).
struct PaperPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(SeenTheme.Paper.accent, in: RoundedRectangle(cornerRadius: SeenTheme.Radius.inline))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Bordered surface button (secondary action).
struct PaperSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(SeenTheme.Paper.ink)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(SeenTheme.Paper.surface, in: RoundedRectangle(cornerRadius: SeenTheme.Radius.inline))
            .overlay(
                RoundedRectangle(cornerRadius: SeenTheme.Radius.inline)
                    .stroke(SeenTheme.Paper.border, lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Hotkey formatting

/// Converts a stored hotkey (virtual key code + Carbon modifier flags — the
/// representation `RegisterEventHotKey` consumes) into human glyphs, and
/// bridges NSEvent modifier flags into Carbon flags when recording.
enum Hotkey {
    /// The modifier + key symbols, in canonical order (⌃ ⌥ ⇧ ⌘ then the key).
    static func symbols(keyCode: Int, carbonModifiers: Int) -> [String] {
        var parts: [String] = []
        if carbonModifiers & controlKey != 0 { parts.append("⌃") }
        if carbonModifiers & optionKey  != 0 { parts.append("⌥") }
        if carbonModifiers & shiftKey   != 0 { parts.append("⇧") }
        if carbonModifiers & cmdKey     != 0 { parts.append("⌘") }
        parts.append(keyName(keyCode))
        return parts
    }

    /// A single joined string, e.g. "⌃⌥⌘S" — for compact hotkey hints.
    static func display(keyCode: Int, carbonModifiers: Int) -> String {
        symbols(keyCode: keyCode, carbonModifiers: carbonModifiers).joined()
    }

    /// Convert live NSEvent modifier flags into Carbon flags for storage.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var carbon = 0
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.option)  { carbon |= optionKey }
        if flags.contains(.shift)   { carbon |= shiftKey }
        if flags.contains(.command) { carbon |= cmdKey }
        return carbon
    }

    static func modifierCount(_ carbonModifiers: Int) -> Int {
        [controlKey, optionKey, shiftKey, cmdKey].filter { carbonModifiers & $0 != 0 }.count
    }

    static func keyName(_ code: Int) -> String {
        let names: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
            38: "J", 40: "K", 45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7",
            28: "8", 25: "9", 29: "0",
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Escape",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        return names[code] ?? "Key\(code)"
    }
}
