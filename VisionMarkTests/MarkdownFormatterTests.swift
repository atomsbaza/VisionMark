import XCTest
import AppKit
@testable import VisionMark

final class MarkdownFormatterTests: XCTestCase {
    private func attributed(_ lines: [(String, NSFont)]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            result.append(NSAttributedString(string: line.0, attributes: [.font: line.1]))
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        return result
    }

    private func bodyFont(size: CGFloat = 12) -> NSFont {
        NSFont.systemFont(ofSize: size)
    }

    private func boldFont(size: CGFloat = 12) -> NSFont {
        NSFontManager.shared.convert(NSFont.systemFont(ofSize: size), toHaveTrait: .boldFontMask)
    }

    private func italicFont(size: CGFloat = 12) -> NSFont {
        NSFontManager.shared.convert(NSFont.systemFont(ofSize: size), toHaveTrait: .italicFontMask)
    }

    func testSingleParagraphNoHeadings() {
        let input = attributed([("Just a plain paragraph.", bodyFont())])
        let doc = MarkdownFormatter.format(input)
        XCTAssertEqual(doc.blocks, [.paragraph(runs: [InlineRun(text: "Just a plain paragraph.")])])
    }

    func testHeadingDetectionBySize() {
        let input = attributed([
            ("Title", bodyFont(size: 24)),
            ("", bodyFont()),
            ("Body text here.", bodyFont(size: 12)),
        ])
        let doc = MarkdownFormatter.format(input)
        XCTAssertEqual(doc.blocks, [
            .heading(level: .h1, runs: [InlineRun(text: "Title")]),
            .paragraph(runs: [InlineRun(text: "Body text here.")]),
        ])
    }

    func testThreeHeadingLevels() {
        let input = attributed([
            ("Big Title", bodyFont(size: 24)),
            ("", bodyFont()),
            ("Subtitle", bodyFont(size: 18)),
            ("", bodyFont()),
            ("Sub-subtitle", bodyFont(size: 14)),
            ("", bodyFont()),
            ("Body text.", bodyFont(size: 12)),
        ])
        let doc = MarkdownFormatter.format(input)
        XCTAssertEqual(doc.blocks, [
            .heading(level: .h1, runs: [InlineRun(text: "Big Title")]),
            .heading(level: .h2, runs: [InlineRun(text: "Subtitle")]),
            .heading(level: .h3, runs: [InlineRun(text: "Sub-subtitle")]),
            .paragraph(runs: [InlineRun(text: "Body text.")]),
        ])
    }

    func testBoldAndItalicInlineRuns() {
        let mixed = NSMutableAttributedString()
        mixed.append(NSAttributedString(string: "Normal ", attributes: [.font: bodyFont()]))
        mixed.append(NSAttributedString(string: "bold", attributes: [.font: boldFont()]))
        mixed.append(NSAttributedString(string: " and ", attributes: [.font: bodyFont()]))
        mixed.append(NSAttributedString(string: "italic", attributes: [.font: italicFont()]))
        mixed.append(NSAttributedString(string: ".", attributes: [.font: bodyFont()]))

        let doc = MarkdownFormatter.format(mixed)
        XCTAssertEqual(doc.blocks.count, 1)
        guard case .paragraph(let runs) = doc.blocks[0] else {
            return XCTFail("Expected a single paragraph block")
        }
        let rendered = runs.map(\.rendered).joined()
        XCTAssertEqual(rendered, "Normal **bold** and *italic*.")
    }

    func testBulletListDetection() {
        let input = attributed([
            ("• First item", bodyFont()),
            ("• Second item", bodyFont()),
            ("", bodyFont()),
            ("Regular paragraph.", bodyFont()),
        ])
        let doc = MarkdownFormatter.format(input)
        XCTAssertEqual(doc.blocks, [
            .listItem(runs: [InlineRun(text: "First item")]),
            .listItem(runs: [InlineRun(text: "Second item")]),
            .paragraph(runs: [InlineRun(text: "Regular paragraph.")]),
        ])
    }

    func testWrappedLinesJoinIntoOneParagraph() {
        let input = attributed([
            ("This sentence wraps", bodyFont()),
            ("onto a second line.", bodyFont()),
            ("", bodyFont()),
            ("A new paragraph.", bodyFont()),
        ])
        let doc = MarkdownFormatter.format(input)
        XCTAssertEqual(doc.blocks, [
            .paragraph(runs: [InlineRun(text: "This sentence wraps"), InlineRun(text: " "), InlineRun(text: "onto a second line.")]),
            .paragraph(runs: [InlineRun(text: "A new paragraph.")]),
        ])
    }

    func testSingleUniformFontSizeProducesNoHeadings() {
        let input = attributed([
            ("Line one.", bodyFont()),
            ("", bodyFont()),
            ("Line two.", bodyFont()),
        ])
        let doc = MarkdownFormatter.format(input)
        for block in doc.blocks {
            if case .heading = block {
                XCTFail("Should not detect headings when all text is the same size")
            }
        }
    }

    func testEmptyInputProducesNoBlocks() {
        let doc = MarkdownFormatter.format(NSAttributedString(string: ""))
        XCTAssertTrue(doc.blocks.isEmpty)
    }

}
