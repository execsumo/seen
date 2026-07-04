import CoreGraphics
import CoreText
import Foundation
import ImageIO
import SeenKit
import UniformTypeIdentifiers

// MARK: - Synthetic image helpers

/// A solid-color bitmap `CGImage` of the given dimensions.
private func makeSolidImage(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

/// Renders `text` in white on a black background with CoreText so Vision can OCR it.
private func makeTextImage(_ text: String, width: Int = 600, height: Int = 160) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let font = CTFontCreateWithName("Menlo" as CFString, 60, nil)
    let attributes: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
    ]
    let attributed = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
    let line = CTLineCreateWithAttributedString(attributed)
    context.textPosition = CGPoint(x: 30, y: 40)
    CTLineDraw(line, context)
    return context.makeImage()!
}

/// Decodes encoded image data back to its pixel dimensions via ImageIO.
private func decodeSize(_ data: Data) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    return (image.width, image.height)
}

private func makeTempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private func config(in directory: URL, maxDimension: Int = 1568) -> CaptureConfiguration {
    CaptureConfiguration(saveDirectoryPath: directory.path, defaultMaxDimension: maxDimension)
}

// MARK: - Mocks

private final class MockCapturer: ScreenCapturing, @unchecked Sendable {
    var frames: [CapturedFrame] = []
    var throwOnCapture: SeenError?
    func displays() async throws -> [DisplayInfo] { [] }
    func applications() async throws -> [AppWindowInfo] { [] }
    func hasScreenRecordingPermission() async -> Bool { true }
    func capture(_ target: CaptureRequest.Target) async throws -> [CapturedFrame] {
        if let error = throwOnCapture { throw error }
        return frames
    }
}

private final class MockRecognizer: TextRecognizing, @unchecked Sendable {
    var receivedImage: CGImage?
    var result: String?
    func recognizeText(in image: CGImage) async throws -> String? {
        receivedImage = image
        return result
    }
}

private final class MockEncoder: ImageEncoding, @unchecked Sendable {
    var receivedImage: CGImage?
    var receivedOptions: EncodingOptions?
    var outputWidth = 100
    var outputHeight = 100
    func encode(_ image: CGImage, options: EncodingOptions) throws -> EncodedImage {
        receivedImage = image
        receivedOptions = options
        return EncodedImage(data: Data([0x00]), format: options.format, width: outputWidth, height: outputHeight)
    }
}

private final class MockStore: CaptureStoring, @unchecked Sendable {
    let directory: URL
    private(set) var calls: [(label: String, timestamp: Date)] = []
    init(directory: URL) { self.directory = directory }
    func store(_ image: EncodedImage, sourceLabel: String, timestamp: Date) throws -> URL {
        calls.append((sourceLabel, timestamp))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("mock-\(calls.count).\(image.format.fileExtension)")
        try image.data.write(to: url)
        return url
    }
}

/// Collects events from `@Sendable` observer closures. The coordinator emits
/// synchronously during `perform`, so by the time `perform` returns the box is
/// fully populated; `@unchecked Sendable` is safe under that sequential use.
private final class EventBox: @unchecked Sendable {
    var events: [CaptureEvent] = []
}

// MARK: - Tests

let coreEngineTests: [TestCase] = [
    // MARK: Coordinator

    TestCase("coordinator: .image output leaves text nil and skips OCR") {
        let dir = makeTempDir()
        let capturer = MockCapturer()
        capturer.frames = [CapturedFrame(
            image: makeSolidImage(width: 50, height: 50, red: 0.2, green: 0.4, blue: 0.6),
            sourceLabel: "display-1"
        )]
        let recognizer = MockRecognizer()
        recognizer.result = "should be ignored"
        let coordinator = CaptureCoordinator(
            capturer: capturer, recognizer: recognizer,
            encoder: MockEncoder(), store: MockStore(directory: dir),
            configurationProvider: { config(in: dir) }
        )

        let result = try await coordinator.perform(CaptureRequest(output: .image))
        try expectEqual(result.items.count, 1)
        try expectEqual(result.items[0].text, nil as String?)
        try expect(recognizer.receivedImage == nil, "OCR must not run when output is image-only")
    },

    TestCase("coordinator: .both output carries recognized text") {
        let dir = makeTempDir()
        let capturer = MockCapturer()
        capturer.frames = [CapturedFrame(
            image: makeSolidImage(width: 40, height: 40, red: 0, green: 0, blue: 0),
            sourceLabel: "display-1"
        )]
        let recognizer = MockRecognizer()
        recognizer.result = "hello world"
        let coordinator = CaptureCoordinator(
            capturer: capturer, recognizer: recognizer,
            encoder: MockEncoder(), store: MockStore(directory: dir),
            configurationProvider: { config(in: dir) }
        )

        let result = try await coordinator.perform(CaptureRequest(output: .both))
        try expectEqual(result.items[0].text, "hello world")
    },

    TestCase("coordinator: .text output saves image and reports empty string when OCR finds nothing") {
        let dir = makeTempDir()
        let capturer = MockCapturer()
        capturer.frames = [CapturedFrame(
            image: makeSolidImage(width: 40, height: 40, red: 0, green: 0, blue: 0),
            sourceLabel: "display-1"
        )]
        let recognizer = MockRecognizer()
        recognizer.result = nil
        let store = MockStore(directory: dir)
        let coordinator = CaptureCoordinator(
            capturer: capturer, recognizer: recognizer,
            encoder: MockEncoder(), store: store,
            configurationProvider: { config(in: dir) }
        )

        let result = try await coordinator.perform(CaptureRequest(output: .text))
        try expectEqual(result.items.count, 1)
        try expectEqual(result.items[0].text, "")
        try expect(store.calls.count == 1, "image must be saved even for text-only output")
    },

    TestCase("coordinator: OCR receives full-res image while stored image is downscaled") {
        let dir = makeTempDir()
        let capturer = MockCapturer()
        capturer.frames = [CapturedFrame(
            image: makeSolidImage(width: 2000, height: 2000, red: 0.1, green: 0.2, blue: 0.3),
            sourceLabel: "display-1"
        )]
        let recognizer = MockRecognizer()
        recognizer.result = "text"
        let provider: @Sendable () -> CaptureConfiguration = { config(in: dir, maxDimension: 1568) }
        let coordinator = CaptureCoordinator(
            capturer: capturer, recognizer: recognizer,
            encoder: ImageIOEncoder(),
            store: DirectoryCaptureStore(configurationProvider: provider),
            configurationProvider: provider
        )

        let result = try await coordinator.perform(CaptureRequest(output: .both))
        try expectEqual(result.items.count, 1)
        // OCR saw the original full-resolution frame.
        try expectEqual(recognizer.receivedImage?.width, 2000)
        try expectEqual(recognizer.receivedImage?.height, 2000)
        // The stored image was downscaled to the configured longest-edge cap.
        try expectEqual(result.items[0].width, 1568)
        try expectEqual(result.items[0].height, 1568)
        try expect(FileManager.default.fileExists(atPath: result.items[0].path), "file should be on disk")
    },

    TestCase("coordinator: failure emits .captureFailed then rethrows") {
        let dir = makeTempDir()
        let capturer = MockCapturer()
        capturer.throwOnCapture = .targetNotFound("nope")
        let coordinator = CaptureCoordinator(
            capturer: capturer, recognizer: MockRecognizer(),
            encoder: MockEncoder(), store: MockStore(directory: dir),
            configurationProvider: { config(in: dir) }
        )
        let box = EventBox()
        await coordinator.observeEvents { box.events.append($0) }

        let error = try await expectThrows { _ = try await coordinator.perform(CaptureRequest()) }
        try expect(error is SeenError, "expected SeenError, got \(error)")
        try expectEqual(box.events.count, 1)
        guard case .captureFailed(let message) = box.events[0] else {
            throw ExpectationFailure(message: "expected .captureFailed event, got \(box.events[0])", file: #filePath, line: #line)
        }
        try expect(message.contains("nope"), "failure message should mention the target, got \(message)")
    },

    TestCase("coordinator: events reach multiple observers") {
        let dir = makeTempDir()
        let capturer = MockCapturer()
        capturer.frames = [CapturedFrame(
            image: makeSolidImage(width: 16, height: 16, red: 0, green: 0, blue: 0),
            sourceLabel: "display-1"
        )]
        let coordinator = CaptureCoordinator(
            capturer: capturer, recognizer: MockRecognizer(),
            encoder: MockEncoder(), store: MockStore(directory: dir),
            configurationProvider: { config(in: dir) }
        )
        let boxA = EventBox()
        let boxB = EventBox()
        await coordinator.observeEvents { boxA.events.append($0) }
        await coordinator.observeEvents { boxB.events.append($0) }

        _ = try await coordinator.perform(CaptureRequest(output: .image))
        try expectEqual(boxA.events.count, 1)
        try expectEqual(boxB.events.count, 1)
        guard case .captureCompleted = boxA.events[0] else {
            throw ExpectationFailure(message: "expected .captureCompleted for observer A", file: #filePath, line: #line)
        }
        guard case .captureCompleted = boxB.events[0] else {
            throw ExpectationFailure(message: "expected .captureCompleted for observer B", file: #filePath, line: #line)
        }
    },

    // MARK: Encoder

    TestCase("encoder: downscale math caps longest edge, preserves aspect, never upscales") {
        let encoder = ImageIOEncoder()
        let opts = { (format: ImageFormat, maxDim: Int?) in
            EncodingOptions(format: format, quality: 1, maxDimension: maxDim)
        }

        // Landscape: 3000x1500 -> longest edge 3000 capped to 1568 -> 1568x784.
        let landscape = makeSolidImage(width: 3000, height: 1500, red: 0.3, green: 0.3, blue: 0.3)
        let r1 = try encoder.encode(landscape, options: opts(.png, 1568))
        try expectEqual(r1.width, 1568)
        try expectEqual(r1.height, 784)

        // Portrait: 1500x3000 -> 784x1568.
        let portrait = makeSolidImage(width: 1500, height: 3000, red: 0.3, green: 0.3, blue: 0.3)
        let r2 = try encoder.encode(portrait, options: opts(.png, 1568))
        try expectEqual(r2.width, 784)
        try expectEqual(r2.height, 1568)

        // No upscale: 100x50 with cap 1568 stays 100x50.
        let tiny = makeSolidImage(width: 100, height: 50, red: 0.3, green: 0.3, blue: 0.3)
        let r3 = try encoder.encode(tiny, options: opts(.png, 1568))
        try expectEqual(r3.width, 100)
        try expectEqual(r3.height, 50)

        // No cap: original size preserved.
        let r4 = try encoder.encode(landscape, options: opts(.png, nil))
        try expectEqual(r4.width, 3000)
        try expectEqual(r4.height, 1500)
    },

    TestCase("encoder: jpeg round-trip preserves dimensions") {
        let encoder = ImageIOEncoder()
        let image = makeSolidImage(width: 200, height: 100, red: 0.5, green: 0.2, blue: 0.8)
        let encoded = try encoder.encode(image, options: EncodingOptions(format: .jpeg, quality: 0.8, maxDimension: nil))
        try expectEqual(encoded.format, .jpeg)
        guard let size = decodeSize(encoded.data) else {
            throw ExpectationFailure(message: "could not decode jpeg", file: #filePath, line: #line)
        }
        try expectEqual(size.width, 200)
        try expectEqual(size.height, 100)
    },

    TestCase("encoder: png round-trip preserves dimensions") {
        let encoder = ImageIOEncoder()
        let image = makeSolidImage(width: 200, height: 100, red: 0.5, green: 0.2, blue: 0.8)
        let encoded = try encoder.encode(image, options: EncodingOptions(format: .png, quality: 1, maxDimension: nil))
        try expectEqual(encoded.format, .png)
        guard let size = decodeSize(encoded.data) else {
            throw ExpectationFailure(message: "could not decode png", file: #filePath, line: #line)
        }
        try expectEqual(size.width, 200)
        try expectEqual(size.height, 100)
    },

    TestCase("encoder: webp encodes or throws unsupportedFormat per OS support") {
        let encoder = ImageIOEncoder()
        let image = makeSolidImage(width: 64, height: 64, red: 0.4, green: 0.4, blue: 0.4)
        let options = EncodingOptions(format: .webp, quality: 0.8, maxDimension: nil)
        let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        let webpSupported = writable.contains(UTType.webP.identifier)

        if webpSupported {
            let encoded = try encoder.encode(image, options: options)
            try expectEqual(encoded.format, .webp)
            try expect(encoded.data.count > 0, "webp data should be non-empty")
        } else {
            let error = try await expectThrows { _ = try encoder.encode(image, options: options) }
            guard let seen = error as? SeenError, case .unsupportedFormat = seen else {
                throw ExpectationFailure(message: "expected .unsupportedFormat, got \(error)", file: #filePath, line: #line)
            }
        }
    },

    // MARK: Store

    TestCase("store: filename convention matches CaptureFileNaming") {
        let dir = makeTempDir()
        let store = DirectoryCaptureStore(configurationProvider: { config(in: dir) })
        let timestamp = Date(timeIntervalSince1970: 1_782_136_222) // 2026-06-22 13:50:22 UTC
        let image = EncodedImage(data: Data([0xFF, 0xD8, 0xFF]), format: .jpeg, width: 10, height: 10)

        let url = try store.store(image, sourceLabel: "display-1", timestamp: timestamp)
        let expected = CaptureFileNaming.filename(timestamp: timestamp, sourceLabel: "display-1", format: .jpeg)
        try expectEqual(url.lastPathComponent, expected)
        try expect(FileManager.default.fileExists(atPath: url.path), "file should exist")
    },

    TestCase("store: auto-creates a missing save directory") {
        let dir = makeTempDir().appendingPathComponent("nested/deeper", isDirectory: true)
        try expect(!FileManager.default.fileExists(atPath: dir.path), "precondition: directory must not exist yet")
        let store = DirectoryCaptureStore(configurationProvider: { config(in: dir) })
        let image = EncodedImage(data: Data([0x89, 0x50]), format: .png, width: 4, height: 4)

        let url = try store.store(image, sourceLabel: "display-1", timestamp: Date(timeIntervalSince1970: 0))
        try expect(FileManager.default.fileExists(atPath: dir.path), "directory should be created")
        try expect(FileManager.default.fileExists(atPath: url.path), "file should exist")
    },

    TestCase("store: appends -2, -3 on filename collisions") {
        let dir = makeTempDir()
        let store = DirectoryCaptureStore(configurationProvider: { config(in: dir) })
        let timestamp = Date(timeIntervalSince1970: 1_782_136_222)
        let image = EncodedImage(data: Data([0xFF]), format: .jpeg, width: 8, height: 8)

        let first = try store.store(image, sourceLabel: "display-1", timestamp: timestamp)
        let second = try store.store(image, sourceLabel: "display-1", timestamp: timestamp)
        let third = try store.store(image, sourceLabel: "display-1", timestamp: timestamp)

        let stem = (first.lastPathComponent as NSString).deletingPathExtension
        let ext = (first.lastPathComponent as NSString).pathExtension
        try expectEqual(second.lastPathComponent, "\(stem)-2.\(ext)")
        try expectEqual(third.lastPathComponent, "\(stem)-3.\(ext)")
        try expect(FileManager.default.fileExists(atPath: first.path))
        try expect(FileManager.default.fileExists(atPath: second.path))
        try expect(FileManager.default.fileExists(atPath: third.path))
    },

    // MARK: OCR

    TestCase("ocr: recognizes rendered text (case-insensitive containment)") {
        let recognizer = VisionTextRecognizer()
        let image = makeTextImage("SeenKit")
        let text = try await recognizer.recognizeText(in: image)
        try expect(text != nil, "expected some recognized text, got nil")
        try expect((text ?? "").lowercased().contains("seen"), "expected 'seen' in '\(text ?? "")'")
    },

    TestCase("ocr: blank image returns nil (no recognizable text)") {
        let recognizer = VisionTextRecognizer()
        let image = makeSolidImage(width: 200, height: 200, red: 0, green: 0, blue: 0)
        let text = try await recognizer.recognizeText(in: image)
        try expectEqual(text, nil as String?)
    },
]
