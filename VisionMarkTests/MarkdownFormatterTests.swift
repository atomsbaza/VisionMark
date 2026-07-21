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

    private func monoFont(size: CGFloat = 12) -> NSFont {
        NSFont(name: "Menlo", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
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

    // MARK: - R1: hyphenation repair at line-merge seam

    func testHyphenJoinBasic() {
        XCTAssertTrue(MarkdownFormatter.shouldJoinHyphenated(lastText: "con-", nextText: "verting"))

        let input = attributed([
            ("This is a con-", bodyFont()),
            ("verting example.", bodyFont()),
        ])
        let doc = MarkdownFormatter.format(input)
        XCTAssertEqual(doc.blocks.count, 1)
        guard case .paragraph(let runs) = doc.blocks[0] else {
            return XCTFail("Expected a single paragraph block")
        }
        XCTAssertEqual(runs.map(\.rendered).joined(), "This is a converting example.")
    }

    func testHyphenJoinKeepsSpaceWhenNextStartsUppercase() {
        XCTAssertFalse(MarkdownFormatter.shouldJoinHyphenated(lastText: "Anthropic-", nextText: "Claude"))

        let input = attributed([
            ("Built by Anthropic-", bodyFont()),
            ("Claude is great.", bodyFont()),
        ])
        let doc = MarkdownFormatter.format(input)
        guard case .paragraph(let runs) = doc.blocks[0] else {
            return XCTFail("Expected a single paragraph block")
        }
        XCTAssertEqual(runs.map(\.rendered).joined(), "Built by Anthropic- Claude is great.")
    }

    func testHyphenJoinKeepsSpaceWhenDigitPrecedesHyphen() {
        XCTAssertFalse(MarkdownFormatter.shouldJoinHyphenated(lastText: "Section 2-", nextText: "next info here."))

        let input = attributed([
            ("Section 2-", bodyFont()),
            ("next info here.", bodyFont()),
        ])
        let doc = MarkdownFormatter.format(input)
        guard case .paragraph(let runs) = doc.blocks[0] else {
            return XCTFail("Expected a single paragraph block")
        }
        XCTAssertEqual(runs.map(\.rendered).joined(), "Section 2- next info here.")
    }

    func testHyphenJoinPreservesRunTraitsAcrossSeam() {
        let mixed = NSMutableAttributedString()
        mixed.append(NSAttributedString(string: "auto-", attributes: [.font: boldFont()]))
        mixed.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont()]))
        mixed.append(NSAttributedString(string: "matic behavior.", attributes: [.font: bodyFont()]))

        let doc = MarkdownFormatter.format(mixed)
        XCTAssertEqual(doc.blocks.count, 1)
        guard case .paragraph(let runs) = doc.blocks[0] else {
            return XCTFail("Expected a single paragraph block")
        }
        XCTAssertEqual(runs, [
            InlineRun(text: "auto", isBold: true),
            InlineRun(text: "matic behavior.", isBold: false),
        ])
        XCTAssertEqual(runs.map(\.rendered).joined(), "**auto**matic behavior.")
    }

    // MARK: - R2: monospace code-block grouping

    func testConsecutiveMonospaceLinesGroupIntoOneCodeBlock() {
        let input = attributed([
            ("func foo() {", monoFont()),
            ("    return 1", monoFont()),
            ("}", monoFont()),
        ])
        let doc = MarkdownFormatter.format(input)
        XCTAssertEqual(doc.blocks, [
            .codeBlock(lines: ["func foo() {", "return 1", "}"]),
        ])
    }

    func testIsolatedMonospaceLineBecomesOneLineCodeBlock() {
        let input = attributed([
            ("Some prose above.", bodyFont()),
            ("", bodyFont()),
            ("let x = 1", monoFont()),
            ("", bodyFont()),
            ("Some prose below.", bodyFont()),
        ])
        let doc = MarkdownFormatter.format(input)
        XCTAssertEqual(doc.blocks, [
            .paragraph(runs: [InlineRun(text: "Some prose above.")]),
            .codeBlock(lines: ["let x = 1"]),
            .paragraph(runs: [InlineRun(text: "Some prose below.")]),
        ])
    }

    func testMixedDocumentProseIsUnaffectedByCodeDetection() {
        let input = attributed([
            ("This paragraph wraps", bodyFont()),
            ("onto a second line.", bodyFont()),
            ("", bodyFont()),
            ("print(\"hi\")", monoFont()),
            ("", bodyFont()),
            ("Another normal paragraph.", bodyFont()),
        ])
        let doc = MarkdownFormatter.format(input)
        XCTAssertEqual(doc.blocks, [
            .paragraph(runs: [InlineRun(text: "This paragraph wraps"), InlineRun(text: " "), InlineRun(text: "onto a second line.")]),
            .codeBlock(lines: ["print(\"hi\")"]),
            .paragraph(runs: [InlineRun(text: "Another normal paragraph.")]),
        ])
    }

    func testNonMonospaceDocumentProducesNoCodeBlocks() {
        let input = attributed([
            ("Line one.", bodyFont()),
            ("", bodyFont()),
            ("Line two.", bodyFont()),
        ])
        let doc = MarkdownFormatter.format(input)
        for block in doc.blocks {
            if case .codeBlock = block {
                XCTFail("Non-monospace document should never produce a code block")
            }
        }
    }

    func testCodeLinesAreExcludedFromBodyFontHistogram() {
        // Many monospace "code" lines share the SAME font size as the heading (24pt). If code
        // lines counted toward the body-font histogram, their sheer count would make 24pt look
        // like the body size (not a heading size), suppressing heading detection entirely (R2-AC6).
        var lines: [(String, NSFont)] = [("Title", bodyFont(size: 24)), ("", bodyFont())]
        for i in 0..<10 {
            lines.append(("code line \(i)", monoFont(size: 24)))
            lines.append(("", bodyFont()))
        }
        lines.append(("Body paragraph.", bodyFont(size: 12)))

        let input = attributed(lines)
        let doc = MarkdownFormatter.format(input)
        let headings = doc.blocks.compactMap { block -> HeadingLevel? in
            if case .heading(let level, _) = block { return level }
            return nil
        }
        XCTAssertEqual(headings, [.h1], "Title should still be detected as a heading despite many same-size code lines")
    }
}
