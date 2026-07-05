import XCTest
import AppKit
@testable import VisionMark

/// Tests for the document-wide (global) body-font baseline (R4): heading classification should
/// use a histogram merged across pages, not a per-page one, so sparse pages (e.g. a slide whose
/// most-common font is its own title) still get their titles promoted to headings.
final class GlobalHeadingBaselineTests: XCTestCase {
    private func attributed(_ lines: [(String, CGFloat)]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            result.append(NSAttributedString(string: line.0, attributes: [.font: NSFont.systemFont(ofSize: line.1)]))
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        return result
    }

    private func headingLevels(in doc: MarkdownDocument) -> [HeadingLevel] {
        doc.blocks.compactMap { block -> HeadingLevel? in
            if case .heading(let level, _) = block { return level }
            return nil
        }
    }

    /// A sparse "slide" page whose only paragraph is a large title (font 24). With no other
    /// paragraphs on the page, per-page `bodyFontSize` picks 24 as the body size (it's the only
    /// size present), so nothing clears the 1.15x heading threshold and the title is NOT
    /// classified as a heading. Two other pages establish a document-wide body size of 12, so
    /// against the global baseline the same title (24 >> 12 * 1.15) IS promoted to a heading.
    func testGlobalBaselinePromotesTitleThatPerPageBaselineMisses() {
        let slidePage = attributed([
            ("Sparse Slide Title", 24),
        ])

        let bodyPageA = attributed([
            ("Some intro text.", 12),
            ("", 12),
            ("This is a normal body paragraph at the common document font size.", 12),
            ("", 12),
            ("Another normal body paragraph at the common document font size.", 12),
        ])
        let bodyPageB = attributed([
            ("More body text here.", 12),
            ("", 12),
            ("Yet another paragraph reinforcing the common body font size across pages.", 12),
            ("", 12),
            ("And one more paragraph at the same common size.", 12),
        ])

        // Per-page formatting misses the heading entirely on the sparse slide.
        let perPageDoc = MarkdownFormatter.format(slidePage)
        XCTAssertTrue(headingLevels(in: perPageDoc).isEmpty, "Per-page baseline should miss the heading on a sparse slide")

        // Merge histograms across all three "pages" to compute the global baseline.
        var globalHistogram: [CGFloat: Int] = [:]
        for page in [slidePage, bodyPageA, bodyPageB] {
            for (bucket, count) in MarkdownFormatter.bodyFontHistogram(for: page) {
                globalHistogram[bucket, default: 0] += count
            }
        }
        let globalBodySize = MarkdownFormatter.bodySize(fromHistogram: globalHistogram)
        XCTAssertEqual(globalBodySize, 12, "Global body size should be the common 12pt size across pages")

        let globalDoc = MarkdownFormatter.format(slidePage, bodySize: globalBodySize)
        XCTAssertEqual(headingLevels(in: globalDoc), [.h1], "Global baseline should promote the sparse slide's title to a heading")
    }

    /// Regression (R4-AC2/R5): on a clean single-column page that already classifies well,
    /// formatting against the (matching) global baseline should produce identical headings to
    /// the existing per-page `format(_:)`.
    func testCleanSingleColumnPageHeadingsUnchangedWithGlobalBaseline() {
        let page = attributed([
            ("Document Title", 22),
            ("", 12),
            ("This is the first body paragraph of a clean, well-formed single-column document.", 12),
            ("", 12),
            ("This is the second body paragraph reinforcing the same common body font size.", 12),
            ("", 12),
            ("This is the third body paragraph, also at the common body font size.", 12),
        ])

        let perPageDoc = MarkdownFormatter.format(page)
        let perPageHeadings = headingLevels(in: perPageDoc)
        XCTAssertEqual(perPageHeadings, [.h1])

        let globalHistogram = MarkdownFormatter.bodyFontHistogram(for: page)
        let globalBodySize = MarkdownFormatter.bodySize(fromHistogram: globalHistogram)
        let globalDoc = MarkdownFormatter.format(page, bodySize: globalBodySize)

        XCTAssertEqual(headingLevels(in: globalDoc), perPageHeadings, "Headings should be unchanged on already-good input")
    }
}
