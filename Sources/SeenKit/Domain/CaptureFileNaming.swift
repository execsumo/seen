import Foundation

/// The one place capture filenames are produced, so the naming convention
/// (`capture_2026-07-03_13-50-22_display-1.jpg`) can't drift between the
/// storage layer and anything that parses filenames later.
public enum CaptureFileNaming {
    /// - Parameters:
    ///   - timeZone: injectable for deterministic tests; defaults to local time,
    ///     which is what users expect when browsing their screenshots folder.
    public static func filename(
        timestamp: Date,
        sourceLabel: String?,
        format: ImageFormat,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stamp = formatter.string(from: timestamp)

        let label = sourceLabel.map(sanitize) ?? ""
        return label.isEmpty
            ? "capture_\(stamp).\(format.fileExtension)"
            : "capture_\(stamp)_\(label).\(format.fileExtension)"
    }

    /// Lowercases and reduces a source label to `[a-z0-9-]`, collapsing runs
    /// of other characters into single dashes: `"Google Chrome"` → `"google-chrome"`.
    public static func sanitize(_ label: String) -> String {
        var result = ""
        var pendingDash = false
        for scalar in label.lowercased().unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                if pendingDash, !result.isEmpty { result.append("-") }
                pendingDash = false
                result.unicodeScalars.append(scalar)
            } else {
                pendingDash = true
            }
        }
        return result
    }
}
