import XCTest
@testable import VisionMark

final class PageClassifierTests: XCTestCase {
    func testWellPopulatedTextPageDoesNotNeedOCR() {
        let classifier = PageClassifier()
        // Letter-size page, ~500 characters of body text.
        XCTAssertFalse(classifier.needsOCR(nonWhitespaceCharacterCount: 500, pageArea: 612 * 792))
    }

    func testNearEmptyPageNeedsOCR() {
        let classifier = PageClassifier()
        XCTAssertTrue(classifier.needsOCR(nonWhitespaceCharacterCount: 3, pageArea: 612 * 792))
    }

    func testScannedPageWithNoExtractableTextNeedsOCR() {
        let classifier = PageClassifier()
        XCTAssertTrue(classifier.needsOCR(nonWhitespaceCharacterCount: 0, pageArea: 612 * 792))
    }

    func testZeroAreaPageNeedsOCR() {
        let classifier = PageClassifier()
        XCTAssertTrue(classifier.needsOCR(nonWhitespaceCharacterCount: 500, pageArea: 0))
    }

    func testSparseTextOnLargePageNeedsOCR() {
        let classifier = PageClassifier()
        // Just above the absolute floor, but far too sparse for a large page (e.g. a caption on a scanned image).
        XCTAssertTrue(classifier.needsOCR(nonWhitespaceCharacterCount: 25, pageArea: 612 * 792))
    }

    func testCustomThresholdsAreRespected() {
        let lenient = PageClassifier(densityThreshold: 0, minimumCharacterCount: 0)
        XCTAssertFalse(lenient.needsOCR(nonWhitespaceCharacterCount: 1, pageArea: 612 * 792))

        let strict = PageClassifier(densityThreshold: .greatestFiniteMagnitude, minimumCharacterCount: .max)
        XCTAssertTrue(strict.needsOCR(nonWhitespaceCharacterCount: 10_000, pageArea: 612 * 792))
    }
}
