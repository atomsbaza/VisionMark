import Foundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

enum PDFTextExtractorError: Error, Sendable {
    case unreadableFile
    case locked
}

/// Renders a single PDF page to a `CGImage` at a bounded resolution, suitable for OCR.
/// Not `Sendable` itself (holds no cross-actor state) — call from within the pipeline actor.
enum PDFPageRenderer {
    static func renderImage(for page: PDFPage, targetDPI: CGFloat = 220, maxDimension: CGFloat = 4000) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let scale = min(targetDPI / 72.0, maxDimension / max(bounds.width, bounds.height))
        let pixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: Int(pixelSize.width),
                height: Int(pixelSize.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: pixelSize))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)

        page.draw(with: .mediaBox, to: context)

        return context.makeImage()
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }
}
