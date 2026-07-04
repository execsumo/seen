import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ImageIO-backed implementation of `ImageEncoding`.
///
/// Downscales the longest edge to `options.maxDimension` (aspect ratio preserved,
/// never upscaling) via CoreGraphics, then encodes the result with
/// `CGImageDestination`. JPEG, PNG, and HEIC are always supported; WebP is
/// encoded only when the OS reports it as a writable destination type, otherwise
/// `SeenError.unsupportedFormat` is thrown.
public final class ImageIOEncoder: ImageEncoding {

    /// Creates an encoder that downscales via CoreGraphics and writes via ImageIO.
    public init() {}

    /// Downscales (preserving aspect ratio, never upscaling) and encodes. Throws
    /// `SeenError.unsupportedFormat` when the OS can't encode `options.format`.
    public func encode(_ image: CGImage, options: EncodingOptions) throws -> EncodedImage {
        let format = options.format
        if format == .webp {
            try ensureWebPSupported()
        }

        let scaled = downscale(image, maxDimension: options.maxDimension)
        let typeID = typeIdentifier(for: format)

        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer as CFMutableData,
            typeID as CFString,
            1,
            nil
        ) else {
            throw SeenError.encodingFailed("could not create image destination for \(format.rawValue)")
        }

        // Lossy formats honour the quality setting; PNG is lossless and ignores it.
        if format == .jpeg || format == .heic || format == .webp {
            CGImageDestinationAddImage(
                destination,
                scaled,
                [kCGImageDestinationLossyCompressionQuality: options.quality] as CFDictionary
            )
        } else {
            CGImageDestinationAddImage(destination, scaled, nil)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw SeenError.encodingFailed("failed to finalize \(format.rawValue) encoding")
        }

        return EncodedImage(
            data: buffer as Data,
            format: format,
            width: scaled.width,
            height: scaled.height
        )
    }

    // MARK: - Downscaling

    /// Returns `image` unchanged when no cap is set or the image already fits
    /// within it; otherwise returns a new CGImage with its longest edge clamped to
    /// `maxDimension`, preserving aspect ratio and never upscaling.
    private func downscale(_ image: CGImage, maxDimension: Int?) -> CGImage {
        guard let maxDimension else { return image }
        let originalWidth = image.width
        let originalHeight = image.height
        let longestEdge = max(originalWidth, originalHeight)
        guard longestEdge > maxDimension, longestEdge > 0 else { return image }

        let scale = CGFloat(maxDimension) / CGFloat(longestEdge)
        let newWidth = max(1, Int((CGFloat(originalWidth) * scale).rounded()))
        let newHeight = max(1, Int((CGFloat(originalHeight) * scale).rounded()))

        guard let context = makeContext(width: newWidth, height: newHeight, colorSpace: image.colorSpace) else {
            return image
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage() ?? image
    }

    private func makeContext(width: Int, height: Int, colorSpace: CGColorSpace?) -> CGContext? {
        let space = colorSpace ?? CGColorSpaceCreateDeviceRGB()
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    // MARK: - Format support

    /// Throws `unsupportedFormat` when this OS cannot write WebP via ImageIO.
    private func ensureWebPSupported() throws {
        let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        let webpID = UTType.webP.identifier
        guard writable.contains(webpID) else {
            throw SeenError.unsupportedFormat("webp (\(webpID)) is not writable on this system")
        }
    }

    private func typeIdentifier(for format: ImageFormat) -> String {
        switch format {
        case .jpeg: return UTType.jpeg.identifier
        case .png: return UTType.png.identifier
        case .heic: return UTType.heic.identifier
        case .webp: return UTType.webP.identifier
        }
    }
}
