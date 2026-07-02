import Foundation
import Vision
import CoreGraphics

enum OCREngineError: Error, Sendable {
    case recognitionFailed(String)
}

/// Wraps Vision text recognition for scanned/image-only PDF pages.
/// Stateless — safe to call concurrently from multiple tasks.
private struct RecognizedLine: Sendable {
    let text: String
    let midY: CGFloat
    let height: CGFloat
}

struct OCREngine: Sendable {
    func recognizeText(in image: CGImage) async throws -> [Block] {
        let lines: [RecognizedLine] = try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCREngineError.recognitionFailed(error.localizedDescription))
                    return
                }
                // Extract plain Sendable data here — VNRecognizedTextObservation itself
                // is not Sendable and must not cross the continuation boundary.
                let results = (request.results as? [VNRecognizedTextObservation]) ?? []
                let extracted: [RecognizedLine] = results.compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let box = observation.boundingBox
                    return RecognizedLine(text: candidate.string, midY: box.midY, height: box.height)
                }
                continuation.resume(returning: extracted)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCREngineError.recognitionFailed(error.localizedDescription))
            }
        }

        return paragraphs(from: lines)
    }

    /// Groups recognized lines into paragraphs by vertical gap, top-to-bottom reading order.
    /// OCR output carries no font metadata, so every paragraph is emitted as plain text
    /// (no heading/bold inference for OCR'd pages).
    private func paragraphs(from lines: [RecognizedLine]) -> [Block] {
        let lines = lines
            .sorted { $0.midY > $1.midY } // Vision's coordinate origin is bottom-left; top-to-bottom means descending midY.

        guard !lines.isEmpty else { return [] }

        var blocks: [Block] = []
        var currentParagraphLines: [String] = [lines[0].text]
        var previous = lines[0]

        for line in lines.dropFirst() {
            let gap = previous.midY - line.midY
            let averageHeight = (previous.height + line.height) / 2
            if averageHeight > 0 && gap > averageHeight * 1.6 {
                blocks.append(.paragraph(runs: [InlineRun(text: currentParagraphLines.joined(separator: " "))]))
                currentParagraphLines = []
            }
            currentParagraphLines.append(line.text)
            previous = line
        }
        if !currentParagraphLines.isEmpty {
            blocks.append(.paragraph(runs: [InlineRun(text: currentParagraphLines.joined(separator: " "))]))
        }
        return blocks
    }
}
