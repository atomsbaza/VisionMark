import Foundation
import Observation

@Observable
@MainActor
final class ConversionViewModel {
    private(set) var jobs: [ConversionJob] = []
    private(set) var isConverting = false

    private let settings: AppSettings
    private var conversionTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func addFiles(_ urls: [URL]) {
        let pdfURLs = urls.flatMap(Self.expandToPDFs)
        let existingSources = Set(jobs.map(\.sourceURL))
        let newJobs = pdfURLs
            .filter { !existingSources.contains($0) }
            .map { ConversionJob(sourceURL: $0) }
        jobs.append(contentsOf: newJobs)
    }

    func clearCompleted() {
        jobs.removeAll { job in
            if case .done = job.status { return true }
            return false
        }
    }

    func convertAll() {
        guard !isConverting else { return }
        isConverting = true
        let outputDirectory = settings.resolvedOutputDirectory()
        let ocrMode = settings.ocrMode
        let embedImages = settings.embedPageImages
        let pendingIndices = jobs.indices.filter { index in
            if case .queued = jobs[index].status { return true }
            if case .failed = jobs[index].status { return true }
            return false
        }

        conversionTask = Task { [weak self] in
            guard let self else { return }
            let maxConcurrent = max(1, min(ProcessInfo.processInfo.activeProcessorCount, 4))
            var iterator = pendingIndices.makeIterator()

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<maxConcurrent {
                    guard let index = iterator.next() else { break }
                    group.addTask { await self.runConversion(jobIndex: index, outputDirectory: outputDirectory, ocrMode: ocrMode, embedImages: embedImages) }
                }
                while await group.next() != nil {
                    if let index = iterator.next() {
                        group.addTask { await self.runConversion(jobIndex: index, outputDirectory: outputDirectory, ocrMode: ocrMode, embedImages: embedImages) }
                    }
                }
            }
            self.isConverting = false
        }
    }

    func cancelAll() {
        conversionTask?.cancel()
        isConverting = false
    }

    private func runConversion(jobIndex: Int, outputDirectory: URL?, ocrMode: OCRMode, embedImages: Bool) async {
        guard jobIndex < jobs.count else { return }
        let sourceURL = jobs[jobIndex].sourceURL
        jobs[jobIndex].status = .converting(progress: 0)

        let classifier: PageClassifier
        switch ocrMode {
        case .autoDetect:
            classifier = PageClassifier()
        case .always:
            classifier = PageClassifier(densityThreshold: .greatestFiniteMagnitude, minimumCharacterCount: .max)
        case .never:
            classifier = PageClassifier(densityThreshold: 0, minimumCharacterCount: 0)
        }
        let pipeline = ConversionPipeline(classifier: classifier)

        do {
            let outputURL = try await pipeline.convert(source: sourceURL, outputDirectory: outputDirectory, embedImages: embedImages) { [weak self] progress in
                Task { @MainActor in
                    guard let self, jobIndex < self.jobs.count else { return }
                    self.jobs[jobIndex].status = .converting(progress: progress)
                }
            }
            guard jobIndex < jobs.count else { return }
            jobs[jobIndex].status = .done(outputURL: outputURL)
        } catch is CancellationError {
            guard jobIndex < jobs.count else { return }
            jobs[jobIndex].status = .failed(reason: "Cancelled")
        } catch {
            guard jobIndex < jobs.count else { return }
            jobs[jobIndex].status = .failed(reason: error.localizedDescription)
        }
    }

    private static func expandToPDFs(_ url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }

        if isDirectory.boolValue {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []
            return contents.flatMap(expandToPDFs)
        } else if url.pathExtension.lowercased() == "pdf" {
            return [url]
        }
        return []
    }
}
