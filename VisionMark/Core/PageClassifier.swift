import Foundation
import PDFKit

/// Decides whether a PDF page has usable native text or should be routed through OCR.
struct PageClassifier: Sendable {
    /// Minimum non-whitespace characters per 1000 square points of page area
    /// below which a page is considered image-only / scanned.
    var densityThreshold: Double = 0.15

    /// Absolute floor: fewer than this many non-whitespace characters always triggers OCR,
    /// regardless of page size (guards against tiny/degenerate page bounds).
    var minimumCharacterCount: Int = 20

    func needsOCR(nonWhitespaceCharacterCount: Int, pageArea: Double) -> Bool {
        if nonWhitespaceCharacterCount < minimumCharacterCount {
            return true
        }
        guard pageArea > 0 else { return true }
        let density = Double(nonWhitespaceCharacterCount) / (pageArea / 1000.0)
        return density < densityThreshold
    }

    func needsOCR(page: PDFPage) -> Bool {
        let text = page.string ?? ""
        let nonWhitespaceCount = text.unicodeScalars.reduce(into: 0) { count, scalar in
            if !CharacterSet.whitespacesAndNewlines.contains(scalar) {
                count += 1
            }
        }
        let bounds = page.bounds(for: .mediaBox)
        let area = Double(bounds.width * bounds.height)
        return needsOCR(nonWhitespaceCharacterCount: nonWhitespaceCount, pageArea: area)
    }
}
