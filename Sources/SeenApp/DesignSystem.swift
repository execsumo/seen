import SwiftUI
import AppKit
import Carbon
import CoreText

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
}

// MARK: - Theme (DESIGN.md — "High-Performance Terminal")

/// The design system is dark-only by construction: DESIGN.md ships a single
/// palette anchored on a near-black ground, so the app pins itself to the dark
/// appearance rather than resolving two sets of tokens.
enum SeenTheme {
    /// Tokens from DESIGN.md. Where the token block and the prose disagree on
    /// the ground colour, the prose wins: it anchors the palette at `#08080B`
    /// and puts containers at `#121217`, which is the relationship the whole
    /// elevation model depends on (containers must read *above* the ground).
    enum Term {
        // Ground and tonal layers — depth is tonal, never shadow.
        static let base      = Color(hex: "08080B") // window ground
        static let sunken    = Color(hex: "0E0E11") // surface-container-lowest: code blocks
        static let elevated  = Color(hex: "121217") // surface-elevated: cards, panels
        static let raised    = Color(hex: "1B1B1F") // surface-container-low: hover, sidebar
        static let high      = Color(hex: "201F23") // surface-container: pressed, wells

        // Structure — bold 1px borders carry the hierarchy.
        static let border       = Color(hex: "1C1C22") // border-subtle
        static let borderStrong = Color(hex: "524439") // outline-variant

        // Text — the spec's own ramp, brightest to dimmest.
        static let ink   = Color(hex: "E5E1E6") // on-surface: headings
        static let body  = Color(hex: "D7C3B4") // on-surface-variant: parchment body
        static let mute  = Color(hex: "C0B7A9") // on-secondary-container: secondary prose
        static let dim   = Color(hex: "9F8D80") // outline: labels, metadata, hints

        // Primary — warm, high-visibility amber.
        static let amber       = Color(hex: "FFB46E") // primary-container
        static let amberBright = Color(hex: "FFB876") // surface-tint
        static let amberSoft   = Color(hex: "FFD9BA") // primary
        static let onAmber     = Color(hex: "4B2800") // on-primary

        // Terminal accents — syntax, output, status.
        static let green = Color(hex: "A6E22E") // terminal-green
        static let blue  = Color(hex: "66D9EF") // terminal-blue
        static let cyan  = Color(hex: "AAEAFF") // tertiary
        static let error = Color(hex: "FFB4AB") // error

        // Semantic status.
        static let good = green
        static let warn = amber
        static let bad  = error

        /// Backdrop dim for overlays — 80% black, per the spec.
        static let scrim = Color.black.opacity(0.8)
    }

    /// 4px baseline. DESIGN.md calls for 8/16/24/32/48/64 increments; 4 is kept
    /// only for hairline gaps between stacked rows.
    enum Spacing {
        static let hair: CGFloat = 4
        static let sm:   CGFloat = 8
        static let md:   CGFloat = 16
        static let lg:   CGFloat = 24
        static let xl:   CGFloat = 32
        static let xxl:  CGFloat = 48
    }

    /// The shape language is strictly sharp. Nothing in this app rounds.
    static let radius: CGFloat = 0

    /// Every container border in the system is 1px.
    static let hairline: CGFloat = 1
}

// MARK: - Typography (JetBrains Mono, exclusively)

/// Loads the bundled JetBrains Mono faces into the process font registry.
///
/// The faces ship inside the app bundle so the terminal identity holds on a Mac
/// that has never installed the family; if they're missing (a bare `swift run`
/// against a tree without the resource copy), everything falls back to the
/// system monospace face rather than to a proportional one.
enum SeenFonts {
    static let familyName = "JetBrains Mono"

    /// `static let` runs exactly once, lazily, and thread-safely — so this both
    /// performs the registration and records whether the family resolved.
    static let isAvailable: Bool = registerBundledFaces()

    static func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        isAvailable
            ? .custom(familyName, fixedSize: size).weight(weight)
            : .system(size: size, weight: weight, design: .monospaced)
    }

    private static func registerBundledFaces() -> Bool {
        for url in bundledFontURLs() {
            var error: Unmanaged<CFError>?
            // A repeat registration returns false with an "already registered"
            // error; there is nothing useful to do about either outcome, and
            // the resolution check below is the real verdict.
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            error?.release()
        }
        // CTFontCreateWithName silently substitutes a fallback for an unknown
        // name, so ask the created font what family it actually is.
        let probe = CTFontCreateWithName(familyName as CFString, 12, nil)
        return (CTFontCopyFamilyName(probe) as String) == familyName
    }

    private static func bundledFontURLs() -> [URL] {
        var roots: [URL] = []
        if let resources = Bundle.main.resourceURL { roots.append(resources) }
        roots.append(Bundle.main.bundleURL)
        if let exe = Bundle.main.executableURL { roots.append(exe.deletingLastPathComponent()) }

        // `Fonts/` is where scripts/bundle.sh puts them inside the .app;
        // the SwiftPM resource bundle is where `swift run SeenApp` finds them.
        let relativePaths = [
            "Fonts",
            "Seen_SeenApp.bundle/Contents/Resources/Fonts",
            "Seen_SeenApp.bundle/Fonts",
        ]

        let fm = FileManager.default
        var urls: [URL] = []
        for root in roots {
            for relative in relativePaths {
                let dir = root.appendingPathComponent(relative)
                guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
                urls += names.filter { $0.hasSuffix(".ttf") }.sorted().map { dir.appendingPathComponent($0) }
            }
        }
        return urls
    }
}

/// The named type steps from DESIGN.md. Sizes, weights, tracking, and line
/// height come straight from the spec's typography block.
enum SeenType {
    struct Style {
        let size: CGFloat
        let weight: Font.Weight
        /// Absolute tracking in points (the spec's em values × size).
        let tracking: CGFloat
        /// Unitless line height from the spec.
        let lineHeight: CGFloat

        /// Extra leading SwiftUI needs to approximate the spec's line height.
        var lineSpacing: CGFloat { max(0, size * (lineHeight - 1)) }

        func weighted(_ w: Font.Weight) -> Style {
            Style(size: size, weight: w, tracking: tracking, lineHeight: lineHeight)
        }

        func sized(_ s: CGFloat) -> Style {
            Style(size: s, weight: weight, tracking: tracking, lineHeight: lineHeight)
        }
    }

    static let headlineXL = Style(size: 48, weight: .bold,     tracking: -0.96, lineHeight: 1.1)
    static let headlineLG = Style(size: 32, weight: .semibold, tracking: -0.32, lineHeight: 1.2)
    /// `headline-lg-mobile` — the right structural step for a 720pt settings
    /// window, where the 32px headline would swamp the pane.
    static let headlineMD = Style(size: 24, weight: .semibold, tracking: 0,     lineHeight: 1.2)
    static let bodyMD     = Style(size: 16, weight: .regular,  tracking: 0,     lineHeight: 1.6)
    static let bodySM     = Style(size: 14, weight: .regular,  tracking: 0,     lineHeight: 1.5)
    static let label      = Style(size: 12, weight: .medium,   tracking: 0.6,   lineHeight: 1.0)
    static let code       = Style(size: 14, weight: .regular,  tracking: 0,     lineHeight: 1.7)
    /// Sentence-case metadata at label size — the spec reserves all-caps + the
    /// 0.05em tracking for labels proper, so prose at 12px drops the tracking.
    static let caption    = Style(size: 12, weight: .regular,  tracking: 0,     lineHeight: 1.5)
}

struct SeenTypeModifier: ViewModifier {
    let style: SeenType.Style
    func body(content: Content) -> some View {
        content
            .font(SeenFonts.font(style.size, style.weight))
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
    }
}

extension View {
    /// Applies one of the DESIGN.md type steps: face, size, weight, tracking,
    /// and line height together.
    func seenType(_ style: SeenType.Style) -> some View {
        modifier(SeenTypeModifier(style: style))
    }
}

// MARK: - Structural primitives

/// A 1px horizontal rule — the system's unit of structure.
struct HRule: View {
    var color: Color = SeenTheme.Term.border
    var body: some View {
        color.frame(height: SeenTheme.hairline)
    }
}

/// A sharp 1px border drawn inside the view's own bounds.
struct BorderOverlay: ViewModifier {
    let color: Color
    let width: CGFloat
    func body(content: Content) -> some View {
        content.overlay { Rectangle().strokeBorder(color, lineWidth: width) }
    }
}

extension View {
    func terminalBorder(_ color: Color = SeenTheme.Term.border,
                        width: CGFloat = SeenTheme.hairline) -> some View {
        modifier(BorderOverlay(color: color, width: width))
    }
}

// MARK: - SeenMark (app glyph — a sharp terminal enclosure around an eye)

struct SeenMark: View {
    var size: CGFloat = 26

    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 64
            let rect = CGRect(origin: .zero, size: sz)
            let stroke = max(1, 2 * s)

            // Sharp enclosure: sunken ground, amber rule. No radius, no shadow.
            ctx.fill(Path(rect), with: .color(SeenTheme.Term.sunken))
            ctx.stroke(Path(rect.insetBy(dx: stroke / 2, dy: stroke / 2)),
                       with: .color(SeenTheme.Term.amber), lineWidth: stroke)

            // Eye almond, drawn as an outline the way a terminal glyph would be.
            var eye = Path()
            eye.move(to: CGPoint(x: 14 * s, y: 32 * s))
            eye.addQuadCurve(to: CGPoint(x: 50 * s, y: 32 * s),
                             control: CGPoint(x: 32 * s, y: 16 * s))
            eye.addQuadCurve(to: CGPoint(x: 14 * s, y: 32 * s),
                             control: CGPoint(x: 32 * s, y: 48 * s))
            eye.closeSubpath()
            ctx.stroke(eye, with: .color(SeenTheme.Term.amberSoft), lineWidth: max(1, 2.5 * s))

            // Square pupil — the brutalist tell.
            ctx.fill(
                Path(CGRect(x: 26 * s, y: 26 * s, width: 12 * s, height: 12 * s)),
                with: .color(SeenTheme.Term.amber)
            )
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Shared components

/// All-caps metadata label, per the spec's label treatment.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .seenType(SeenType.label.weighted(.semibold))
            .foregroundStyle(SeenTheme.Term.mute)
    }
}

/// A minimalist container: 1px border, tonal lift, square corners. An optional
/// title is separated from the content by a 1px rule, per the spec.
struct SettingsCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                SectionLabel(text: title)
                    .padding(.horizontal, SeenTheme.Spacing.md)
                    .padding(.vertical, SeenTheme.Spacing.sm + 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HRule()
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeenTheme.Term.elevated)
        .terminalBorder()
    }
}

struct CardRow<Content: View>: View {
    var isLast: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, SeenTheme.Spacing.md)
                .padding(.vertical, SeenTheme.Spacing.md - 4)
            if !isLast {
                // Full-bleed: structure is defined by borders, not by insets.
                HRule()
            }
        }
    }
}

/// A sharp-edged tag — the spec's chip, with a monochromatic tint and a border.
struct StatusTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .seenType(SeenType.label.weighted(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, SeenTheme.Spacing.sm)
            .padding(.vertical, SeenTheme.Spacing.hair)
            .background(color.opacity(0.12))
            .terminalBorder(color.opacity(0.45))
    }
}

/// A square status indicator. Circles are off-language here.
struct StatusDot: View {
    let color: Color
    let pulsing: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            if pulsing {
                Rectangle()
                    .fill(color.opacity(pulse ? 0.28 : 0))
                    .frame(width: 16, height: 16)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            }
            Rectangle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .frame(width: 16, height: 16)
        .onAppear { if pulsing { pulse = true } }
    }
}

/// The command-line focus metaphor: a hard-blinking block cursor.
struct BlockCursor: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let lit = Int(ctx.date.timeIntervalSinceReferenceDate / 0.5) % 2 == 0
            Rectangle()
                .fill(SeenTheme.Term.amber)
                .opacity(lit ? 1 : 0)
        }
        .frame(width: 8, height: 16)
    }
}

/// A monospaced list marker, standing in for a bullet.
struct Marker: View {
    var glyph: String = ">"
    var color: Color = SeenTheme.Term.amber
    var body: some View {
        Text(glyph)
            .seenType(SeenType.caption.weighted(.bold))
            .foregroundStyle(color)
    }
}

/// Secondary prose, introduced by a `> ` marker instead of an icon bullet.
struct InfoNote: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: SeenTheme.Spacing.sm) {
            Marker(color: SeenTheme.Term.dim)
            Text(text)
                .seenType(SeenType.caption)
                .foregroundStyle(SeenTheme.Term.mute)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A code block: sunken ground, 1px border, terminal syntax colours.
struct CommandLineText: View {
    let text: String
    var prompt: String = "$"

    var body: some View {
        HStack(spacing: SeenTheme.Spacing.sm) {
            Text(prompt)
                .seenType(SeenType.code.weighted(.bold))
                .foregroundStyle(SeenTheme.Term.green)
            Text(text)
                .seenType(SeenType.code)
                .foregroundStyle(SeenTheme.Term.blue)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SeenTheme.Spacing.md - 4)
        .padding(.vertical, SeenTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeenTheme.Term.sunken)
        .terminalBorder()
    }
}

// MARK: - Key chip (renders a single glyph like ⌘ or S)

struct KeyChip: View {
    let symbol: String
    var body: some View {
        Text(symbol)
            .seenType(SeenType.label.weighted(.semibold).sized(13))
            .foregroundStyle(SeenTheme.Term.amberSoft)
            .frame(minWidth: 18, minHeight: 24)
            .padding(.horizontal, SeenTheme.Spacing.sm)
            .background(SeenTheme.Term.high)
            .terminalBorder(SeenTheme.Term.borderStrong)
    }
}

/// Renders a hotkey as a row of key chips (⌃ ⌥ ⌘ S).
struct KeyChipRow: View {
    let keyCode: Int
    let carbonModifiers: Int

    var body: some View {
        HStack(spacing: SeenTheme.Spacing.hair) {
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
        HStack(spacing: SeenTheme.Spacing.sm) {
            StatusDot(color: dotColor, pulsing: pulsing)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .seenType(SeenType.bodySM.weighted(.semibold))
                    .foregroundStyle(SeenTheme.Term.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .seenType(SeenType.caption)
                    .foregroundStyle(SeenTheme.Term.mute)
                    // Mono is wider than the proportional face this replaced, so
                    // the longer status lines wrap rather than truncate.
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: SeenTheme.Spacing.hair)
            if let trailing { trailing }
        }
        .padding(.horizontal, SeenTheme.Spacing.md - 4)
        .padding(.vertical, SeenTheme.Spacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeenTheme.Term.elevated)
        .terminalBorder()
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
            MenuBarRowLabel(title: title, icon: icon, accent: accent, hotkey: hotkey)
        }
        .buttonStyle(MenuBarRowStyle())
    }
}

/// Shared label so the `Capture App` submenu reads identically to a plain row.
struct MenuBarRowLabel: View {
    let title: String
    let icon: String
    var accent: Bool = false
    var hotkey: String? = nil

    var body: some View {
        HStack(spacing: SeenTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(accent ? SeenTheme.Term.amber : SeenTheme.Term.mute)
                .frame(width: 16, alignment: .center)
            Text(title)
                .seenType(SeenType.bodySM)
                .foregroundStyle(accent ? SeenTheme.Term.amber : SeenTheme.Term.body)
                .lineLimit(1)
            Spacer(minLength: SeenTheme.Spacing.sm)
            if let hotkey {
                Text(hotkey)
                    .seenType(SeenType.caption)
                    .foregroundStyle(SeenTheme.Term.dim)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, SeenTheme.Spacing.sm)
        .padding(.vertical, SeenTheme.Spacing.sm - 1)
    }
}

/// Hover lifts the row onto a tonal layer and marks it with an amber rule on
/// the leading edge; pressing inverts it, per the spec's hover guidance.
struct MenuBarRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuBarRowSurface(isPressed: configuration.isPressed) { configuration.label }
    }
}

struct MenuBarRowSurface<Label: View>: View {
    let isPressed: Bool
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        label
            .background(isPressed ? SeenTheme.Term.high : (hovering ? SeenTheme.Term.raised : Color.clear))
            .overlay(alignment: .leading) {
                SeenTheme.Term.amber
                    .frame(width: 2)
                    .opacity(hovering || isPressed ? 1 : 0)
            }
            .onHover { hovering = $0 }
    }
}

// MARK: - Button styles

/// Primary action: a solid amber rectangle with near-black text. Hover inverts
/// it to an amber-on-ground outline.
struct TerminalPrimaryButtonStyle: ButtonStyle {
    /// Primary buttons stretch by default; standalone actions opt out.
    var fillWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        TerminalButtonSurface(
            label: configuration.label,
            isPressed: configuration.isPressed,
            fillWidth: fillWidth,
            restFill: SeenTheme.Term.amber,
            restText: SeenTheme.Term.onAmber,
            restBorder: SeenTheme.Term.amber,
            hoverFill: .clear,
            hoverText: SeenTheme.Term.amber,
            hoverBorder: SeenTheme.Term.amber,
            pressedFill: SeenTheme.Term.amberBright,
            pressedText: SeenTheme.Term.onAmber,
            weight: .bold
        )
    }
}

/// Secondary action: 1px parchment border, no fill. Hover switches the border
/// and the text to amber and doubles the border weight.
struct TerminalSecondaryButtonStyle: ButtonStyle {
    var fillWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        TerminalButtonSurface(
            label: configuration.label,
            isPressed: configuration.isPressed,
            fillWidth: fillWidth,
            restFill: .clear,
            restText: SeenTheme.Term.body,
            restBorder: SeenTheme.Term.borderStrong,
            hoverFill: .clear,
            hoverText: SeenTheme.Term.amber,
            hoverBorder: SeenTheme.Term.amber,
            pressedFill: SeenTheme.Term.high,
            pressedText: SeenTheme.Term.amber,
            weight: .medium,
            hoverBorderWidth: 2
        )
    }
}

struct TerminalButtonSurface<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let fillWidth: Bool
    let restFill: Color
    let restText: Color
    let restBorder: Color
    let hoverFill: Color
    let hoverText: Color
    let hoverBorder: Color
    let pressedFill: Color
    let pressedText: Color
    let weight: Font.Weight
    var hoverBorderWidth: CGFloat = SeenTheme.hairline

    @State private var hovering = false

    private var fill: Color { isPressed ? pressedFill : (hovering ? hoverFill : restFill) }
    private var text: Color { isPressed ? pressedText : (hovering ? hoverText : restText) }
    private var border: Color { hovering || isPressed ? hoverBorder : restBorder }
    private var borderWidth: CGFloat { hovering || isPressed ? hoverBorderWidth : SeenTheme.hairline }

    var body: some View {
        label
            .seenType(SeenType.label.weighted(weight).sized(13))
            .foregroundStyle(text)
            .padding(.vertical, SeenTheme.Spacing.sm)
            .padding(.horizontal, SeenTheme.Spacing.md - 4)
            .frame(maxWidth: fillWidth ? .infinity : nil)
            .background(fill)
            .terminalBorder(border, width: borderWidth)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

// MARK: - Segmented selector

/// A sharp-edged replacement for `Picker(.segmented)`: adjacent 1px cells with
/// a solid amber fill on the selected one.
struct TerminalSegmented<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .seenType(SeenType.label.weighted(selected ? .bold : .medium).sized(13))
                        .foregroundStyle(selected ? SeenTheme.Term.onAmber : SeenTheme.Term.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SeenTheme.Spacing.sm)
                        .background(selected ? SeenTheme.Term.amber : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < options.count - 1 {
                    SeenTheme.Term.border.frame(width: SeenTheme.hairline)
                }
            }
        }
        .background(SeenTheme.Term.sunken)
        .terminalBorder(SeenTheme.Term.borderStrong)
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
