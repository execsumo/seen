import Foundation

/// Filesystem-backed implementation of `CaptureStoring`.
///
/// Reads the save directory from the injected `configurationProvider` on every
/// call (so settings changes apply live without restarts), creates the directory
/// as needed, and writes files named by `CaptureFileNaming`. On a filename
/// collision it appends `-2`, `-3`, … before the extension until it finds a
/// free name.
public final class DirectoryCaptureStore: CaptureStoring {

    private let configurationProvider: @Sendable () -> CaptureConfiguration

    /// - Parameter configurationProvider: invoked once per store call to read the
    ///   current `saveDirectoryPath` (settings may change between captures).
    public init(configurationProvider: @escaping @Sendable () -> CaptureConfiguration) {
        self.configurationProvider = configurationProvider
    }

    /// Persists `image` to the configured directory using `CaptureFileNaming`,
    /// creating the directory if needed and collision-suffixing as required.
    public func store(_ image: EncodedImage, sourceLabel: String, timestamp: Date) throws -> URL {
        let directory = URL(fileURLWithPath: configurationProvider().saveDirectoryPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let baseName = CaptureFileNaming.filename(
            timestamp: timestamp,
            sourceLabel: sourceLabel,
            format: image.format
        )
        let url = uniqueURL(directory: directory, baseName: baseName)

        do {
            try image.data.write(to: url)
        } catch {
            throw SeenError.storageFailed(error.localizedDescription)
        }
        return url
    }

    /// Resolves filename collisions by inserting `-<n>` before the extension,
    /// starting at `2`: `capture_…_display-1.jpg` → `capture_…_display-1-2.jpg`.
    private func uniqueURL(directory: URL, baseName: String) -> URL {
        let ext = (baseName as NSString).pathExtension
        let stem = (baseName as NSString).deletingPathExtension
        var candidate = directory.appendingPathComponent(baseName)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffixed = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            candidate = directory.appendingPathComponent(suffixed)
            counter += 1
        }
        return candidate
    }
}
