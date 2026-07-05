import Foundation
import PDFKit

enum ConversionPipelineError: Error, Sendable, LocalizedError {
    case unreadableFile
    case locked
    case emptyDocument
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unreadableFile: return "Could not open this PDF."
        case .locked: return "This PDF is password-protected."
        case .emptyDocument: return "This PDF has no pages."
        case .cancelled: return "Conversion was cancelled."
        }
    }
}

/// Orchestrates conversion of a single PDF into a Markdown file: per-page classification,
/// native-text extraction, OCR fallback, and Markdown assembly. All PDFKit/CoreGraphics
/// work happens inside this actor so non-`Sendable` types (`PDFDocument`, `PDFPage`,
/// `CGImage`) never cross an actor boundary.
actor ConversionPipeline {
    private let classifier: PageClassifier
    private let ocrEngine: OCREngine

    init(classifier: PageClassifier = PageClassifier(), ocrEngine: OCREngine = OCREngine()) {
        self.classifier = classifier
        self.ocrEngine = ocrEngine
    }

    func convert(
        source: URL,
        outputDirectory: URL?,
        embedImages: Bool,
        onProgress: @Sendable (Double) -> Void
    ) async throws -> URL {
        guard let document = PDFDocument(url: source) else {
            throw ConversionPipelineError.unreadableFile
        }
        if document.isLocked {
            throw ConversionPipelineError.locked
        }
        let pageCount = document.pageCount
        guard pageCount > 0 else {
            throw ConversionPipelineError.emptyDocument
        }

        let outputURL = try resolveOutputURL(source: source, outputDirectory: outputDirectory)
        let safeBase = String(source.deletingPathExtension().lastPathComponent.map { char -> Character in
            char.isLetter || char.isNumber ? char : "_"
        })
        let assetsDirName = "\(safeBase)_assets"
        let assetsDir = outputURL.deletingLastPathComponent().appendingPathComponent(assetsDirName)
        if embedImages {
            try? FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        }
        let padWidth = pageCount >= 100 ? 3 : 2

        // Pass 1: accumulate a document-wide body-font histogram across native-text pages
        // (attributedString reads only — no rendering, so no autoreleasepool needed). This
        // lets heading classification use a global baseline instead of misfiring on sparse
        // pages whose per-page most-common font is their own title (R4).
        var globalHistogram: [CGFloat: Int] = [:]
        for index in 0..<pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            guard !classifier.needsOCR(page: page), let attributed = page.attributedString else { continue }
            for (bucket, count) in MarkdownFormatter.bodyFontHistogram(for: attributed) {
                globalHistogram[bucket, default: 0] += count
            }
        }
        let globalBodySize = MarkdownFormatter.bodySize(fromHistogram: globalHistogram)

        var pageBlockArrays: [[Block]] = []
        for index in 0..<pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }

            let pageBlocks: [Block]
            if classifier.needsOCR(page: page) {
                pageBlocks = try await ocrBlocks(for: page)
            } else if let attributed = page.attributedString {
                pageBlocks = globalBodySize > 0
                    ? MarkdownFormatter.format(attributed, bodySize: globalBodySize).blocks
                    : MarkdownFormatter.format(attributed).blocks
            } else {
                pageBlocks = try await ocrBlocks(for: page)
            }

            var combinedBlocks = pageBlocks
            if embedImages {
                let pageNumber = index + 1
                let padded = String(format: "%0\(padWidth)d", pageNumber)
                autoreleasepool {
                    if let image = PDFPageRenderer.renderImage(for: page, targetDPI: 150) {
                        let fileName = "page-\(padded).png"
                        let fileURL = assetsDir.appendingPathComponent(fileName)
                        do {
                            try PDFPageRenderer.writePNG(image, to: fileURL)
                            let relativePath = "\(assetsDirName)/\(fileName)"
                            combinedBlocks.insert(
                                .image(altText: "Page \(pageNumber)", relativePath: relativePath),
                                at: 0
                            )
                        } catch {
                            // Skip the image on write failure; keep the extracted text.
                        }
                    }
                }
            }

            pageBlockArrays.append(combinedBlocks)
            onProgress(Double(index + 1) / Double(pageCount))
        }

        pageBlockArrays = OutputCleanup.stripBoilerplate(pageBlockArrays)
        pageBlockArrays = pageBlockArrays.map { page in page.compactMap(OutputCleanup.cleanJunkGlyphs) }
        let allBlocks = OutputCleanup.flatten(pageBlockArrays, embedImages: embedImages)

        let markdown = MarkdownDocument(blocks: allBlocks).rendered
        try markdown.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    private func ocrBlocks(for page: PDFPage) async throws -> [Block] {
        let image = autoreleasepool { PDFPageRenderer.renderImage(for: page) }
        guard let image else { return [] }
        return try await ocrEngine.recognizeText(in: image)
    }

    private func resolveOutputURL(source: URL, outputDirectory: URL?) throws -> URL {
        let directory = outputDirectory ?? source.deletingLastPathComponent()
        let filename = source.deletingPathExtension().lastPathComponent + ".md"
        return directory.appendingPathComponent(filename)
    }
}
