import XCTest
@testable import VisionMark

final class ConversionPipelineTests: XCTestCase {
    private func paragraph(_ text: String) -> Block {
        .paragraph(runs: [InlineRun(text: text)])
    }

    private func heading(_ text: String, level: HeadingLevel = .h1) -> Block {
        .heading(level: level, runs: [InlineRun(text: text)])
    }

    // MARK: - R3-AC1: heading takes priority

    func testPageTitlePrefersFirstHeadingOverParagraph() {
        let blocks: [Block] = [
            paragraph("Intro paragraph before the heading."),
            heading("Chapter One"),
            paragraph("Body text."),
        ]
        XCTAssertEqual(ConversionPipeline.pageTitle(from: blocks), "Chapter One")
    }

    // MARK: - R3-AC2: paragraph fallback and no-text fallback

    func testPageTitleFallsBackToFirstParagraphWhenNoHeading() {
        let blocks: [Block] = [
            paragraph("First paragraph."),
            paragraph("Second paragraph."),
        ]
        XCTAssertEqual(ConversionPipeline.pageTitle(from: blocks), "First paragraph.")
    }

    func testPageTitleIsNilWhenPageHasNoTextBlocks() {
        let blocks: [Block] = [
            .image(altText: "Page 1", relativePath: "assets/page-01.png"),
            .thematicBreak,
        ]
        XCTAssertNil(ConversionPipeline.pageTitle(from: blocks))
    }

    func testPageTitleIsNilForEmptyBlockList() {
        XCTAssertNil(ConversionPipeline.pageTitle(from: []))
    }

    // MARK: - R3-AC3: sanitize + truncate

    func testPageTitleStripsBracketsAndNewlines() {
        let blocks: [Block] = [heading("Chapter [One]\nSubtitle")]
        XCTAssertEqual(ConversionPipeline.pageTitle(from: blocks), "Chapter OneSubtitle")
    }

    func testPageTitleTruncatesAtSixtyCharactersWithEllipsis() {
        let longTitle = String(repeating: "x", count: 80)
        let blocks: [Block] = [heading(longTitle)]
        let title = ConversionPipeline.pageTitle(from: blocks)
        XCTAssertEqual(title, String(repeating: "x", count: 60) + "…")
    }

    func testPageTitleUnderSixtyCharactersIsNotTruncated() {
        let blocks: [Block] = [heading("Short Title")]
        XCTAssertEqual(ConversionPipeline.pageTitle(from: blocks), "Short Title")
    }
}
