import Foundation

/// Orchestrates capture → OCR → encode → store for every capture origin
/// (HTTP API, hotkey, menu, sessions). The single entry point defined by
/// `CaptureCoordinating`; downstream layers depend only on that protocol.
///
/// OCR always runs on the full-resolution frame *before* the encoder downscales,
/// so small text stays readable even when the saved image is shrunk for token
/// economy. Lifecycle events are broadcast to every registered observer.
public actor CaptureCoordinator: CaptureCoordinating {

    private let capturer: any ScreenCapturing
    private let recognizer: any TextRecognizing
    private let encoder: any ImageEncoding
    private let store: any CaptureStoring
    private let configurationProvider: @Sendable () -> CaptureConfiguration

    private var observers: [@Sendable (CaptureEvent) -> Void] = []

    /// Creates a coordinator over the given capturer, recognizer, encoder, and
    /// store, reading live capture defaults from `configurationProvider`.
    public init(
        capturer: any ScreenCapturing,
        recognizer: any TextRecognizing,
        encoder: any ImageEncoding,
        store: any CaptureStoring,
        configurationProvider: @escaping @Sendable () -> CaptureConfiguration
    ) {
        self.capturer = capturer
        self.recognizer = recognizer
        self.encoder = encoder
        self.store = store
        self.configurationProvider = configurationProvider
    }

    /// Capture → OCR (full-res, if requested) → encode → store → result, emitting
    /// `.captureCompleted` on success or `.captureFailed` (then rethrowing) on error.
    public func perform(_ request: CaptureRequest) async throws -> CaptureResult {
        let timestamp = Date()
        do {
            let frames = try await capturer.capture(request.target)
            let options = configurationProvider().encodingOptions(for: request)

            var items: [CaptureResult.Item] = []
            for frame in frames {
                // OCR the full-resolution image first, *then* encode (which may
                // downscale) — text recognition degrades on shrunk images.
                let text: String?
                if request.output.includesText {
                    let recognized = try await recognizer.recognizeText(in: frame.image)
                    text = recognized ?? ""
                } else {
                    text = nil
                }

                let encoded = try encoder.encode(frame.image, options: options)
                let url = try store.store(encoded, sourceLabel: frame.sourceLabel, timestamp: timestamp)

                items.append(CaptureResult.Item(
                    path: url.path,
                    sourceLabel: frame.sourceLabel,
                    width: encoded.width,
                    height: encoded.height,
                    byteSize: encoded.data.count,
                    text: text
                ))
            }

            let result = CaptureResult(items: items, timestamp: timestamp)
            emit(.captureCompleted(result))
            return result
        } catch {
            emit(.captureFailed(Self.failureMessage(for: error)))
            throw error
        }
    }

    /// Registers an observer for capture lifecycle events. Handlers may be
    /// called on any thread; hop to the main actor for UI work.
    public func observeEvents(_ handler: @escaping @Sendable (CaptureEvent) -> Void) {
        observers.append(handler)
    }

    /// Broadcasts an event to every registered observer. Exposed publicly so the
    /// session manager (workstream B) can fan session events through the same
    /// observer set at integration time, keeping a single event bus.
    public func emit(_ event: CaptureEvent) {
        for observer in observers {
            observer(event)
        }
    }

    /// Human-readable detail for a `.captureFailed` payload, preferring
    /// `SeenError.message` for known Seen failures.
    private static func failureMessage(for error: Error) -> String {
        if let seen = error as? SeenError {
            return seen.message
        }
        return String(describing: error)
    }
}
