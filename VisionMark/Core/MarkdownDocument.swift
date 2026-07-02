import Foundation

enum HeadingLevel: Int, Sendable {
    case h1 = 1
    case h2 = 2
    case h3 = 3

    var prefix: String { String(repeating: "#", count: rawValue) + " " }
}

struct InlineRun: Sendable, Equatable {
    var text: String
    var isBold: Bool = false
    var isItalic: Bool = false

    var rendered: String {
        guard !text.isEmpty else { return text }
        var result = text
        if isBold && isItalic {
            result = "***\(result)***"
        } else if isBold {
            result = "**\(result)**"
        } else if isItalic {
            result = "*\(result)*"
        }
        return result
    }
}

enum Block: Sendable, Equatable {
    case heading(level: HeadingLevel, runs: [InlineRun])
    case paragraph(runs: [InlineRun])
    case listItem(runs: [InlineRun])
    case image(altText: String, relativePath: String)

    var markdown: String {
        switch self {
        case .heading(let level, let runs):
            return level.prefix + runs.map(\.rendered).joined()
        case .paragraph(let runs):
            return runs.map(\.rendered).joined()
        case .listItem(let runs):
            return "- " + runs.map(\.rendered).joined()
        case .image(let alt, let path):
            return "![\(alt)](\(path))"
        }
    }
}

struct MarkdownDocument: Sendable {
    var blocks: [Block] = []

    var rendered: String {
        var lines: [String] = []
        for block in blocks {
            lines.append(block.markdown)
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
