import XCTest
import AppKit
@testable import VisionMark

/// Focused tests for the font-size clustering used to infer heading levels,
/// separate from general Markdown formatting behavior.
final class HeadingDetectionTests: XCTestCase {
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

    func testOnlyTwoDistinctSizesYieldsSingleHeadingLevel() {
        let input = attributed([
            ("Section Title", 20),
            ("", 12),
            ("Body one.", 12),
            ("", 12),
            ("Body two.", 12),
            ("", 12),
            ("Body three.", 12),
        ])
        let doc = MarkdownFormatter.format(input)
        let headings = doc.blocks.compactMap { block -> HeadingLevel? in
            if case .heading(let level, _) = block { return level }
            return nil
        }
        XCTAssertEqual(headings, [.h1])
    }

    func testMoreThanThreeDistinctLargerSizesCapAtThreeLevels() {
        let input = attributed([
            ("Size 28", 28),
            ("", 12),
            ("Size 24", 24),
            ("", 12),
            ("Size 20", 20),
            ("", 12),
            ("Size 16", 16),
            ("", 12),
            ("Body baseline.", 12),
            ("", 12),
            ("Body baseline again.", 12),
        ])
        let doc = MarkdownFormatter.format(input)
        let headingLevels = doc.blocks.compactMap { block -> HeadingLevel? in
            if case .heading(let level, _) = block { return level }
            return nil
        }
        // Only the top 3 larger sizes become headings; "Size 16" falls back to body/paragraph.
        XCTAssertEqual(headingLevels, [.h1, .h2, .h3])
        XCTAssertTrue(doc.blocks.contains(.paragraph(runs: [InlineRun(text: "Size 16")])))
    }

    func testMajorityBodySizeIsUsedAsBaselineDespiteOutliers() {
        // Baseline should be established by the most common size (weighted by character count),
        // not simply the smallest or first size encountered.
        let input = attributed([
            ("Heading", 22),
            ("", 12),
            ("This is a long body paragraph that repeats the common font size many times over.", 12),
            ("", 12),
            ("Another long body paragraph reinforcing the same common font size as the baseline.", 12),
            ("", 12),
            ("A short outlier line.", 13),
        ])
        let doc = MarkdownFormatter.format(input)
        let headingLevels = doc.blocks.compactMap { block -> HeadingLevel? in
            if case .heading(let level, _) = block { return level }
            return nil
        }
        XCTAssertEqual(headingLevels, [.h1])
    }

    func testAllSameSizeDocumentHasNoHeadings() {
        let input = attributed([
            ("First line.", 12),
            ("", 12),
            ("Second line.", 12),
        ])
        let doc = MarkdownFormatter.format(input)
        let headingLevels = doc.blocks.compactMap { block -> HeadingLevel? in
            if case .heading = block { return HeadingLevel.h1 }
            return nil
        }
        XCTAssertTrue(headingLevels.isEmpty)
    }
}
