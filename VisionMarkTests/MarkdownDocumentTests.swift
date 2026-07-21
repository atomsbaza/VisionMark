import XCTest
@testable import VisionMark

final class MarkdownDocumentTests: XCTestCase {
    func testCodeBlockRendersAsFencedBlockWithLineBreaksPreserved() {
        let block = Block.codeBlock(lines: ["func foo() {", "    return 1", "}"])
        XCTAssertEqual(block.markdown, "```\nfunc foo() {\n    return 1\n}\n```")
    }

    func testSingleLineCodeBlockRendersAsOneLineFence() {
        let block = Block.codeBlock(lines: ["let x = 1"])
        XCTAssertEqual(block.markdown, "```\nlet x = 1\n```")
    }

    func testDocumentRenderingIncludesCodeBlockFence() {
        let doc = MarkdownDocument(blocks: [
            .paragraph(runs: [InlineRun(text: "Some prose.")]),
            .codeBlock(lines: ["print(1)"]),
        ])
        XCTAssertEqual(doc.rendered, "Some prose.\n\n```\nprint(1)\n```\n")
    }
}
