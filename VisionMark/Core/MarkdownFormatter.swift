import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Converts a page's attributed string (as produced by `PDFPage.attributedString`)
/// into a structured `MarkdownDocument`, inferring headings from font-size clustering,
/// bold/italic from font traits, and bullet lists from leading glyphs.
enum MarkdownFormatter {
    private static let bulletPrefixes: [Character] = ["•", "‣", "◦", "-", "*"]

    private struct ParagraphInfo {
        var runs: [InlineRun]
        var fontSize: CGFloat
        var isBulleted: Bool
        var isEmpty: Bool
        /// True when the line's dominant font is monospaced (R2-AC1). Code lines skip
        /// bullet/heading/paragraph/hyphen handling and are grouped into `.codeBlock`s instead.
        var isCode: Bool = false
        /// Raw (un-marked-up) line text, populated only for code lines — used verbatim in the
        /// rendered code block (R2-AC2).
        var rawText: String = ""
    }

    /// Builds a paragraph-occurrence-weighted, 0.5-bucketed font-size histogram for an
    /// attributed string. Exposed so callers (e.g. the pipeline) can merge histograms across
    /// pages to compute a document-wide body-font baseline (R4).
    static func bodyFontHistogram(for attributedString: NSAttributedString) -> [CGFloat: Int] {
        let paragraphs = extractParagraphs(from: attributedString)
        return bodyFontHistogram(from: paragraphs)
    }

    /// Selects the body font size from a histogram: the size with max weight, ties broken by
    /// the smallest size (body text is conventionally the most compact common size).
    static func bodySize(fromHistogram histogram: [CGFloat: Int]) -> CGFloat {
        guard let maxWeight = histogram.values.max() else { return 0 }
        return histogram.filter { $0.value == maxWeight }.keys.min() ?? 0
    }

    /// Formats using a caller-supplied global body size for heading classification (R4).
    /// When `bodySize <= 0` (degenerate/empty global histogram), falls back to the per-page
    /// `format(_:)` behavior (R4-AC3).
    static func format(_ attributedString: NSAttributedString, bodySize: CGFloat) -> MarkdownDocument {
        guard bodySize > 0 else { return format(attributedString) }
        let paragraphs = extractParagraphs(from: attributedString)
        return format(paragraphs: paragraphs, bodySize: bodySize)
    }

    static func format(_ attributedString: NSAttributedString) -> MarkdownDocument {
        let paragraphs = extractParagraphs(from: attributedString)
        let bodySize = bodySize(fromHistogram: bodyFontHistogram(from: paragraphs))
        return format(paragraphs: paragraphs, bodySize: bodySize)
    }

    private static func format(
        paragraphs: [ParagraphInfo],
        bodySize: CGFloat
    ) -> MarkdownDocument {
        let headingSizes = headingLevelSizes(from: paragraphs, bodySize: bodySize)

        var blocks: [Block] = []
        var pendingParagraphRuns: [InlineRun] = []
        var pendingCodeLines: [String] = []

        func flushParagraph() {
            guard !pendingParagraphRuns.isEmpty else { return }
            blocks.append(.paragraph(runs: pendingParagraphRuns))
            pendingParagraphRuns = []
        }

        func flushCodeBlock() {
            guard !pendingCodeLines.isEmpty else { return }
            blocks.append(.codeBlock(lines: pendingCodeLines))
            pendingCodeLines = []
        }

        for paragraph in paragraphs {
            if paragraph.isCode {
                flushParagraph()
                pendingCodeLines.append(paragraph.rawText)
                continue
            }
            flushCodeBlock()

            if paragraph.isEmpty {
                flushParagraph()
                continue
            }

            if paragraph.isBulleted {
                flushParagraph()
                blocks.append(.listItem(runs: paragraph.runs))
                continue
            }

            if let level = headingLevel(for: paragraph.fontSize, in: headingSizes) {
                flushParagraph()
                blocks.append(.heading(level: level, runs: paragraph.runs))
                continue
            }

            if pendingParagraphRuns.isEmpty {
                pendingParagraphRuns = paragraph.runs
            } else if let lastText = pendingParagraphRuns.last?.text,
                      let firstText = paragraph.runs.first?.text,
                      shouldJoinHyphenated(lastText: lastText, nextText: firstText) {
                var lastRun = pendingParagraphRuns[pendingParagraphRuns.count - 1]
                lastRun.text.removeLast()
                pendingParagraphRuns[pendingParagraphRuns.count - 1] = lastRun
                pendingParagraphRuns.append(contentsOf: paragraph.runs)
            } else {
                pendingParagraphRuns.append(InlineRun(text: " "))
                pendingParagraphRuns.append(contentsOf: paragraph.runs)
            }
        }
        flushParagraph()
        flushCodeBlock()

        return MarkdownDocument(blocks: blocks)
    }

    // MARK: - R1: hyphenation repair at line-merge seam

    /// Decides whether two paragraph-merge seam runs should be joined by removing the trailing
    /// hyphen (no space), rather than the default single-space join. True only when `lastText`
    /// ends with a letter immediately followed by `-`, and `nextText` starts with a lowercase
    /// letter (R1-AC1/AC2/AC3).
    static func shouldJoinHyphenated(lastText: String, nextText: String) -> Bool {
        guard lastText.hasSuffix("-"), lastText.count >= 2 else { return false }
        let beforeHyphen = lastText[lastText.index(lastText.endIndex, offsetBy: -2)]
        guard beforeHyphen.isLetter else { return false }
        guard let firstChar = nextText.first, firstChar.isLowercase else { return false }
        return true
    }

    // MARK: - Paragraph extraction

    private static func extractParagraphs(from attributedString: NSAttributedString) -> [ParagraphInfo] {
        let fullString = attributedString.string as NSString
        var paragraphs: [ParagraphInfo] = []
        var lineStart = 0
        let length = fullString.length

        func processLine(range: NSRange) {
            let lineString = fullString.substring(with: range)
            let trimmed = lineString.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                paragraphs.append(ParagraphInfo(runs: [], fontSize: 0, isBulleted: false, isEmpty: true))
                return
            }

            let lineAttributed = attributedString.attributedSubstring(from: range)
            if let dominant = dominantFont(in: lineAttributed), isMonospace(dominant) {
                paragraphs.append(ParagraphInfo(
                    runs: [],
                    fontSize: dominant.pointSize,
                    isBulleted: false,
                    isEmpty: false,
                    isCode: true,
                    rawText: trimmed
                ))
                return
            }

            let (isBulleted, strippedAttributed) = stripBulletPrefix(lineAttributed)
            let runs = inlineRuns(from: strippedAttributed)
            let fontSize = dominantFontSize(in: strippedAttributed)
            paragraphs.append(ParagraphInfo(runs: runs, fontSize: fontSize, isBulleted: isBulleted, isEmpty: runs.isEmpty))
        }

        while lineStart <= length {
            let searchRange = NSRange(location: lineStart, length: length - lineStart)
            let newlineRange = fullString.range(of: "\n", options: [], range: searchRange)
            if newlineRange.location == NSNotFound {
                if lineStart < length {
                    processLine(range: NSRange(location: lineStart, length: length - lineStart))
                }
                break
            }
            processLine(range: NSRange(location: lineStart, length: newlineRange.location - lineStart))
            lineStart = newlineRange.location + 1
        }

        return paragraphs
    }

    private static func stripBulletPrefix(_ attributed: NSAttributedString) -> (Bool, NSAttributedString) {
        let string = attributed.string
        guard let firstNonSpace = string.firstIndex(where: { !$0.isWhitespace }) else {
            return (false, attributed)
        }
        guard let firstChar = string[firstNonSpace...].first, bulletPrefixes.contains(firstChar) else {
            return (false, attributed)
        }
        // Require the bullet glyph to be followed by whitespace to avoid treating
        // hyphenated words or "*emphasis*" markers as list bullets.
        let afterBulletIndex = string.index(after: firstNonSpace)
        guard afterBulletIndex < string.endIndex, string[afterBulletIndex].isWhitespace else {
            return (false, attributed)
        }
        let nsString = string as NSString
        let bulletNSRange = nsString.range(of: String(firstChar))
        guard bulletNSRange.location != NSNotFound else { return (false, attributed) }
        let afterBullet = NSRange(
            location: bulletNSRange.location + bulletNSRange.length,
            length: nsString.length - bulletNSRange.location - bulletNSRange.length
        )
        let remainder = attributed.attributedSubstring(from: afterBullet)
        let trimmedRemainder = trimLeadingWhitespace(remainder)
        return (true, trimmedRemainder)
    }

    private static func trimLeadingWhitespace(_ attributed: NSAttributedString) -> NSAttributedString {
        let string = attributed.string
        guard let firstNonSpace = string.firstIndex(where: { !$0.isWhitespace }) else {
            return NSAttributedString(string: "")
        }
        let offset = string.distance(from: string.startIndex, to: firstNonSpace)
        let nsString = string as NSString
        return attributed.attributedSubstring(from: NSRange(location: offset, length: nsString.length - offset))
    }

    // MARK: - Inline runs

    private static func inlineRuns(from attributed: NSAttributedString) -> [InlineRun] {
        var runs: [InlineRun] = []
        let fullRange = NSRange(location: 0, length: attributed.length)
        guard fullRange.length > 0 else { return runs }

        attributed.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            let text = (attributed.string as NSString).substring(with: range)
            guard !text.isEmpty else { return }
            let traits = traits(of: value)
            let run = InlineRun(text: text, isBold: traits.bold, isItalic: traits.italic)

            if var last = runs.last, last.isBold == run.isBold, last.isItalic == run.isItalic {
                last.text += run.text
                runs[runs.count - 1] = last
            } else {
                runs.append(run)
            }
        }
        return runs
    }

    private static func traits(of fontAttribute: Any?) -> (bold: Bool, italic: Bool) {
        #if canImport(AppKit)
        guard let font = fontAttribute as? NSFont else { return (false, false) }
        let symbolicTraits = font.fontDescriptor.symbolicTraits
        return (symbolicTraits.contains(.bold), symbolicTraits.contains(.italic))
        #else
        return (false, false)
        #endif
    }

    private static func dominantFontSize(in attributed: NSAttributedString) -> CGFloat {
        #if canImport(AppKit)
        guard attributed.length > 0 else { return 0 }
        var sizes: [CGFloat: Int] = [:]
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length), options: []) { value, range, _ in
            guard let font = value as? NSFont else { return }
            sizes[font.pointSize, default: 0] += range.length
        }
        return sizes.max(by: { $0.value < $1.value })?.key ?? 0
        #else
        return 0
        #endif
    }

    /// The line's dominant font: the font with the greatest length-weighted coverage, same
    /// weighting logic as `dominantFontSize`, applied to the font itself rather than its size
    /// (R2-AC1).
    private static func dominantFont(in attributed: NSAttributedString) -> NSFont? {
        #if canImport(AppKit)
        guard attributed.length > 0 else { return nil }
        var lengths: [String: (font: NSFont, length: Int)] = [:]
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length), options: []) { value, range, _ in
            guard let font = value as? NSFont else { return }
            let key = "\(font.fontName)_\(font.pointSize)"
            lengths[key, default: (font, 0)].length += range.length
        }
        return lengths.values.max(by: { $0.length < $1.length })?.font
        #else
        return nil
        #endif
    }

    /// Whether `font` is monospaced: symbolic trait check first, then a family/name-based
    /// fallback list, since some monospace fonts (e.g. Menlo on macOS) may not consistently
    /// report the `.monoSpace` symbolic trait (R2-AC1).
    static func isMonospace(_ font: NSFont) -> Bool {
        if font.fontDescriptor.symbolicTraits.contains(.monoSpace) { return true }
        let monospaceKeywords = ["Courier", "Menlo", "Monaco", "Mono", "Consolas"]
        let name = font.familyName ?? font.fontName
        return monospaceKeywords.contains { name.range(of: $0, options: .caseInsensitive) != nil }
    }

    // MARK: - Font-size histogram / heading clustering

    private static func bodyFontHistogram(from paragraphs: [ParagraphInfo]) -> [CGFloat: Int] {
        // Weighted by paragraph occurrence (not character count) so that one long heading
        // doesn't outweigh many short body paragraphs.
        var histogram: [CGFloat: Int] = [:]
        for paragraph in paragraphs where !paragraph.isEmpty && !paragraph.isBulleted && !paragraph.isCode {
            let bucket = (paragraph.fontSize * 2).rounded() / 2
            histogram[bucket, default: 0] += 1
        }
        return histogram
    }

    private static func headingLevelSizes(from paragraphs: [ParagraphInfo], bodySize: CGFloat) -> [CGFloat] {
        // Require a proportional jump over body size, not just a fractional point difference,
        // so minor font variation (e.g. a slightly emphasized line) isn't mistaken for a heading.
        let significanceThreshold = bodySize > 0 ? bodySize * 1.15 : 0.5
        let distinctLargerSizes = Set(
            paragraphs
                .filter { !$0.isEmpty && !$0.isBulleted }
                .map { ($0.fontSize * 2).rounded() / 2 }
                .filter { $0 > significanceThreshold }
        )
        return distinctLargerSizes.sorted(by: >).prefix(3).map { $0 }
    }

    private static func headingLevel(for fontSize: CGFloat, in headingSizes: [CGFloat]) -> HeadingLevel? {
        let bucket = (fontSize * 2).rounded() / 2
        guard let index = headingSizes.firstIndex(of: bucket) else { return nil }
        switch index {
        case 0: return .h1
        case 1: return .h2
        default: return .h3
        }
    }
}
