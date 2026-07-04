import CoreGraphics
import Foundation
import Vision

/// Vision-backed implementation of `TextRecognizing`.
///
/// Runs `VNRecognizeTextRequest` at the `.accurate` recognition level with
/// language correction enabled, then joins the recognized strings in natural
/// reading order (top-to-bottom, then left-to-right). Returns `nil` when the
/// image contains no recognizable text. Recognition quality is best on the
/// full-resolution image, so callers should OCR *before* any downscaling.
public final class VisionTextRecognizer: TextRecognizing {

    /// Vertical tolerance (in normalized units) below which two observations are
    /// considered to share a line and are ordered only by their horizontal position.
    private static let lineGroupingTolerance: CGFloat = 0.01

    /// Creates a recognizer configured for accurate, language-corrected OCR.
    public init() {}

    /// Recognized text in natural reading order, or `nil` when the image
    /// contains no recognizable text. Runs on the full-resolution image.
    public func recognizeText(in image: CGImage) async throws -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observations = request.results, !observations.isEmpty else {
            return nil
        }

        // Vision's bounding box is normalized with the origin at the lower-left,
        // so "top" is the largest Y. Sort top-to-bottom, breaking ties left-to-right.
        let ordered = observations.sorted { lhs, rhs in
            let leftTop = lhs.boundingBox.minY
            let rightTop = rhs.boundingBox.minY
            if abs(leftTop - rightTop) > Self.lineGroupingTolerance {
                return leftTop > rightTop
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        let lines = ordered.compactMap { observation -> String? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
