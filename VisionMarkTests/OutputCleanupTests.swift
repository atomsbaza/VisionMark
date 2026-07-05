import XCTest
@testable import VisionMark

final class OutputCleanupTests: XCTestCase {
    private func paragraph(_ text: String) -> Block {
        .paragraph(runs: [InlineRun(text: text)])
    }

    // MARK: - R1: boilerplate stripping

    func testRepeatedShortLineDroppedAcrossFourOrMorePages() {
        let footer = paragraph("Confidential - Acme Inc.")
        let pages: [[Block]] = [
            [paragraph("Page one body."), footer],
            [paragraph("Page two body."), footer],
            [paragraph("Page three body."), footer],
            [paragraph("Page four body."), footer],
        ]
        let result = OutputCleanup.stripBoilerplate(pages)
        for page in result {
            XCTAssertFalse(page.contains(footer), "boilerplate footer should be dropped")
        }
        XCTAssertEqual(result[0], [paragraph("Page one body.")])
    }

    func testLongRepeatedParagraphIsKept() {
        let longText = String(repeating: "This is a long repeated paragraph that exceeds sixty characters. ", count: 1)
        XCTAssertGreaterThanOrEqual(longText.count, 60)
        let longParagraph = paragraph(longText)
        let pages: [[Block]] = [
            [longParagraph], [longParagraph], [longParagraph], [longParagraph],
        ]
        let result = OutputCleanup.stripBoilerplate(pages)
        for page in result {
            XCTAssertTrue(page.contains(longParagraph), "long repeated paragraph must be retained")
        }
    }

    func testLineOnLessThanHalfOfPagesIsKept() {
        let occasional = paragraph("Appendix note.")
        let pages: [[Block]] = [
            [paragraph("Body 1."), occasional],
            [paragraph("Body 2.")],
            [paragraph("Body 3.")],
            [paragraph("Body 4.")],
        ]
        let result = OutputCleanup.stripBoilerplate(pages)
        XCTAssertTrue(result[0].contains(occasional))
    }

    func testShortLineOnAtLeastFourPagesIsDroppedEvenBelowHalf() {
        // 12-page doc: footer on 4 pages (33% < 50%, but >= absolute threshold of 4) -> dropped.
        let footer = paragraph("This page intentionally left blank")
        var pages: [[Block]] = (1...12).map { [paragraph("Body \($0).")] }
        for i in 0..<4 { pages[i].append(footer) }
        let result = OutputCleanup.stripBoilerplate(pages)
        for page in result {
            XCTAssertFalse(page.contains(footer), "short line on >=4 pages should be dropped even below 50%")
        }
    }

    func testShortLineOnFewerThanFourPagesBelowHalfIsKept() {
        // 12-page doc: line on only 3 pages (< 4 absolute and < 50%) -> retained.
        let occasional = paragraph("Note.")
        var pages: [[Block]] = (1...12).map { [paragraph("Body \($0).")] }
        for i in 0..<3 { pages[i].append(occasional) }
        let result = OutputCleanup.stripBoilerplate(pages)
        XCTAssertTrue(result[0].contains(occasional), "line on <4 pages and <50% must be kept")
    }

    func testDocumentsWithFewerThanFourPagesAreUntouched() {
        let footer = paragraph("Repeated footer text")
        let pages: [[Block]] = [
            [paragraph("Body 1."), footer],
            [paragraph("Body 2."), footer],
            [paragraph("Body 3."), footer],
        ]
        let result = OutputCleanup.stripBoilerplate(pages)
        XCTAssertEqual(result, pages)
    }

    func testImageBlocksAreNeverDroppedAsBoilerplate() {
        let image = Block.image(altText: "Page 1", relativePath: "assets/page-01.png")
        let pages: [[Block]] = [
            [image], [image], [image], [image],
        ]
        let result = OutputCleanup.stripBoilerplate(pages)
        for page in result {
            XCTAssertEqual(page, [image])
        }
    }

    // MARK: - R2: junk-glyph cleanup

    func testOneOrTwoCharacterNoiseBlockIsDropped() {
        XCTAssertNil(OutputCleanup.cleanJunkGlyphs(paragraph("*")))
        XCTAssertNil(OutputCleanup.cleanJunkGlyphs(paragraph("--")))
    }

    func testLeadingDecorativeGlyphIsStripped() {
        let block = paragraph("+ Actual content here")
        let cleaned = OutputCleanup.cleanJunkGlyphs(block)
        XCTAssertEqual(cleaned, paragraph("Actual content here"))
    }

    func testAlphanumericContentIsUntouched() {
        let block = paragraph("Regular sentence with no glyphs.")
        XCTAssertEqual(OutputCleanup.cleanJunkGlyphs(block), block)
    }

    // MARK: - R3: page separators

    func testImageModeInsertsSeparatorsBetweenPages() {
        let pages: [[Block]] = [
            [.image(altText: "Page 1", relativePath: "p1.png"), paragraph("A")],
            [.image(altText: "Page 2", relativePath: "p2.png"), paragraph("B")],
            [.image(altText: "Page 3", relativePath: "p3.png"), paragraph("C")],
        ]
        let flattened = OutputCleanup.flatten(pages, embedImages: true)
        let separatorCount = flattened.filter { $0 == .thematicBreak }.count
        XCTAssertEqual(separatorCount, pages.count - 1)
    }

    func testTextOnlyModeInsertsNoSeparators() {
        let pages: [[Block]] = [
            [paragraph("A")],
            [paragraph("B")],
            [paragraph("C")],
        ]
        let flattened = OutputCleanup.flatten(pages, embedImages: false)
        XCTAssertFalse(flattened.contains(.thematicBreak))
    }
}
