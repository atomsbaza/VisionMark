import Foundation

enum ConversionStatus: Sendable, Equatable {
    case queued
    case converting(progress: Double)
    case done(outputURL: URL)
    case failed(reason: String)
}

struct ConversionJob: Identifiable, Sendable, Equatable {
    let id: UUID
    let sourceURL: URL
    var status: ConversionStatus

    init(sourceURL: URL, status: ConversionStatus = .queued) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.status = status
    }
}
