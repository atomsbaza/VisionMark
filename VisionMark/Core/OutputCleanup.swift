import Foundation

/// Stage-1 output-quality passes applied across a document's per-page block arrays, before
/// flattening into the final Markdown block stream. Pure/free functions so they're directly
/// unit-testable without a real PDF (see `VisionMarkTests/OutputCleanupTests.swift`).
enum OutputCleanup {
    /// Decorative glyphs that may prefix a block's first run as noise (R2-AC2).
    private static let decorativeGlyphs: Set<Character> = ["+", "‹", "›"]

    /// Plain text for a block, used for boilerplate/junk detection. Image and thematic-break
    /// blocks have no text and are never candidates for stripping (R1-AC5).
    static func plainText(of block: Block) -> String {
        switch block {
        case .heading(_, let runs), .paragraph(let runs), .listItem(let runs):
            return runs.map(\.text).joined()
        case .image, .thematicBreak:
            return ""
        }
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isTextBlock(_ block: Block) -> Bool {
        switch block {
        case .heading, .paragraph, .listItem: return true
        case .image, .thematicBreak: return false
        }
    }

    // MARK: - R1: boilerplate stripping

    /// A short text block repeated verbatim on at least this many pages is treated as boilerplate
    /// regardless of the 50%-of-pages ratio. Catches low-frequency-but-clearly-repeated noise in
    /// long documents — running headers/footers and "This page intentionally left blank" — that
    /// sits below the ratio threshold (R1, absolute-count rule).
    private static let absolutePageThreshold = 4

    /// Drops text blocks that are repeated boilerplate on a majority of pages, OR verbatim on at
    /// least `absolutePageThreshold` pages. No-ops when `pages.count < 4` (R1-AC4). Never touches
    /// `.image` blocks (R1-AC5).
    static func stripBoilerplate(_ pages: [[Block]]) -> [[Block]] {
        let pageCount = pages.count
        guard pageCount >= 4 else { return pages }

        var pageCountByKey: [String: Int] = [:]
        for page in pages {
            var keysSeenOnThisPage: Set<String> = []
            for block in page where isTextBlock(block) {
                let key = normalized(plainText(of: block))
                keysSeenOnThisPage.insert(key)
            }
            for key in keysSeenOnThisPage {
                pageCountByKey[key, default: 0] += 1
            }
        }

        let ratioThreshold = Int((Double(pageCount) * 0.5).rounded(.up))

        return pages.map { page in
            page.filter { block in
                guard isTextBlock(block) else { return true }
                let key = normalized(plainText(of: block))
                let count = pageCountByKey[key] ?? 0
                let isRepeated = count >= ratioThreshold || count >= absolutePageThreshold
                let isShort = key.count < 60
                return !(isRepeated && isShort)
            }
        }
    }

    // MARK: - R2: junk-glyph cleanup

    /// Drops pure-noise blocks (1-2 non-alphanumeric characters) and strips a single leading
    /// decorative glyph + trailing space from a text block's first run.
    static func cleanJunkGlyphs(_ block: Block) -> Block? {
        guard isTextBlock(block) else { return block }

        let text = plainText(of: block)
        let normalizedText = normalized(text)
        if !normalizedText.isEmpty,
           normalizedText.count <= 2,
           !normalizedText.contains(where: { $0.isLetter || $0.isNumber }) {
            return nil
        }

        return stripLeadingDecorativeGlyph(from: block)
    }

    private static func stripLeadingDecorativeGlyph(from block: Block) -> Block {
        func stripped(_ runs: [InlineRun]) -> [InlineRun] {
            guard var firstRun = runs.first else { return runs }
            let text = firstRun.text
            guard let firstChar = text.first, decorativeGlyphs.contains(firstChar) else { return runs }
            let afterGlyph = text.index(after: text.startIndex)
            guard afterGlyph < text.endIndex, text[afterGlyph] == " " else { return runs }
            let afterSpace = text.index(after: afterGlyph)
            firstRun.text = String(text[afterSpace...])
            var newRuns = runs
            newRuns[0] = firstRun
            return newRuns
        }

        switch block {
        case .heading(let level, let runs):
            return .heading(level: level, runs: stripped(runs))
        case .paragraph(let runs):
            return .paragraph(runs: stripped(runs))
        case .listItem(let runs):
            return .listItem(runs: stripped(runs))
        case .image, .thematicBreak:
            return block
        }
    }

    // MARK: - R3: page separators

    /// Flattens per-page block arrays, inserting a `.thematicBreak` between consecutive
    /// non-empty pages only when `embedImages` is true (R3-AC1/AC2).
    static func flatten(_ pages: [[Block]], embedImages: Bool) -> [Block] {
        var result: [Block] = []
        var isFirstNonEmptyPage = true
        for page in pages {
            guard !page.isEmpty else { continue }
            if embedImages && !isFirstNonEmptyPage {
                result.append(.thematicBreak)
            }
            result.append(contentsOf: page)
            isFirstNonEmptyPage = false
        }
        return result
    }
}
