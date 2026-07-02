import SwiftUI
import AppKit

struct FileRowView: View {
    let job: ConversionJob

    var body: some View {
        HStack(spacing: 12) {
            iconBadge

            VStack(alignment: .leading, spacing: 2) {
                Text(job.sourceURL.lastPathComponent)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                secondaryLine
            }

            Spacer(minLength: 8)

            StatusPill(status: job.status)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .animation(.smooth, value: job.status)
    }

    private var iconBadge: some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: "doc.richtext")
                    .foregroundStyle(.tint)
            )
    }

    @ViewBuilder
    private var secondaryLine: some View {
        switch job.status {
        case .queued:
            Text("Waiting…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .converting:
            Text("Converting…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .done(let outputURL):
            Text(outputURL.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        case .failed(let reason):
            Text(reason)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }
}

private struct StatusPill: View {
    let status: ConversionStatus

    var body: some View {
        switch status {
        case .queued:
            pill(label: "Queued", systemImage: "clock", tint: .secondary, background: .secondary.opacity(0.15))

        case .converting(let progress):
            HStack(spacing: 6) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 90)
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.12), in: Capsule())

        case .done(let outputURL):
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Done")
                    Image(systemName: "arrow.up.forward")
                        .font(.caption2)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")

        case .failed:
            pill(label: "Failed", systemImage: "exclamationmark.triangle.fill", tint: .red, background: Color.red.opacity(0.15))
        }
    }

    private func pill(label: String, systemImage: String, tint: Color, background: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(label)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(background, in: Capsule())
    }
}
