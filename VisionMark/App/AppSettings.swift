import Foundation
import Observation

enum OCRMode: String, CaseIterable, Sendable, Identifiable {
    case autoDetect
    case always
    case never

    var id: String { rawValue }

    var label: String {
        switch self {
        case .autoDetect: return "Auto-detect"
        case .always: return "Always OCR"
        case .never: return "Never — text only"
        }
    }
}

@Observable
@MainActor
final class AppSettings {
    private enum Keys {
        static let ocrMode = "ocrMode"
        static let outputDirectoryBookmark = "outputDirectoryBookmark"
        static let useSourceFolderForOutput = "useSourceFolderForOutput"
        static let embedPageImages = "embedPageImages"
    }

    var ocrMode: OCRMode {
        didSet { UserDefaults.standard.set(ocrMode.rawValue, forKey: Keys.ocrMode) }
    }

    var useSourceFolderForOutput: Bool {
        didSet { UserDefaults.standard.set(useSourceFolderForOutput, forKey: Keys.useSourceFolderForOutput) }
    }

    var embedPageImages: Bool {
        didSet { UserDefaults.standard.set(embedPageImages, forKey: Keys.embedPageImages) }
    }

    private(set) var outputDirectoryURL: URL?

    init() {
        let defaults = UserDefaults.standard
        self.ocrMode = OCRMode(rawValue: defaults.string(forKey: Keys.ocrMode) ?? "") ?? .autoDetect
        self.useSourceFolderForOutput = defaults.object(forKey: Keys.useSourceFolderForOutput) as? Bool ?? true
        self.embedPageImages = defaults.object(forKey: Keys.embedPageImages) as? Bool ?? true

        if let bookmarkData = defaults.data(forKey: Keys.outputDirectoryBookmark) {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                outputDirectoryURL = url
                if isStale, let refreshedBookmarkData = try? url.bookmarkData() {
                    defaults.set(refreshedBookmarkData, forKey: Keys.outputDirectoryBookmark)
                }
            }
        }
    }

    func setOutputDirectory(_ url: URL) {
        guard let bookmarkData = try? url.bookmarkData() else { return }
        UserDefaults.standard.set(bookmarkData, forKey: Keys.outputDirectoryBookmark)
        outputDirectoryURL = url
    }

    func resolvedOutputDirectory() -> URL? {
        useSourceFolderForOutput ? nil : outputDirectoryURL
    }
}
