// Deterministic check of the exact code path SeenFonts uses at launch.
// Usage: swift FontCheck.swift <path to Seen.app>
import Foundation
import CoreText
import AppKit

let familyName = "JetBrains Mono"
guard CommandLine.arguments.count > 1 else {
    print("usage: swift FontCheck.swift <path to Seen.app>"); exit(2)
}
let appURL = URL(fileURLWithPath: CommandLine.arguments[1])
let fontsDir = appURL.appendingPathComponent("Contents/Resources/Fonts")

let fm = FileManager.default
guard let names = try? fm.contentsOfDirectory(atPath: fontsDir.path) else {
    print("FAIL: no Fonts directory at \(fontsDir.path)"); exit(1)
}
let ttfs = names.filter { $0.hasSuffix(".ttf") }.sorted()
print("bundled faces (\(ttfs.count)): \(ttfs.joined(separator: ", "))")

for name in ttfs {
    var error: Unmanaged<CFError>?
    let url = fontsDir.appendingPathComponent(name) as CFURL
    let okReg = CTFontManagerRegisterFontsForURL(url, .process, &error)
    print("  register \(name): \(okReg ? "ok" : "already/failed")")
    error?.release()
}

// The same probe SeenFonts.registerBundledFaces() uses.
let probe = CTFontCreateWithName(familyName as CFString, 12, nil)
let resolved = CTFontCopyFamilyName(probe) as String
print("resolved family for \"\(familyName)\": \"\(resolved)\"")

// Confirm each weight maps to a distinct real face, not one face faked four ways.
var faces: [String] = []
for (label, weight) in [("regular", NSFont.Weight.regular), ("medium", .medium),
                        ("semibold", .semibold), ("bold", .bold)] {
    let desc = NSFontDescriptor(fontAttributes: [
        .family: familyName,
        .traits: [NSFontDescriptor.TraitKey.weight: weight],
    ])
    if let f = NSFont(descriptor: desc, size: 13) {
        faces.append("\(label)=\(f.fontName)")
    } else {
        faces.append("\(label)=<nil>")
    }
}
print("weights: \(faces.joined(separator: ", "))")

// A monospaced face must advance every glyph identically at exactly 0.6em.
if let f = NSFont(name: familyName, size: 100) {
    let adv = ["i", "W", "0", "l"].map { s -> CGFloat in
        (s as NSString).size(withAttributes: [.font: f]).width
    }
    print("advances at 100pt for i/W/0/l: \(adv)")
    let uniform = adv.allSatisfy { abs($0 - adv[0]) < 0.01 }
    let correct = abs(adv[0] - 60.0) < 0.5
    print(uniform && correct ? "advance check: PASS (uniform, 0.6em)"
                             : "advance check: FAIL (uniform=\(uniform), 0.6em=\(correct))")
}

if resolved == familyName {
    print("RESULT: PASS — JetBrains Mono resolved from the bundle, no fallback")
    exit(0)
} else {
    print("RESULT: FAIL — fell back to \"\(resolved)\"; the app will render in the wrong face")
    exit(1)
}
