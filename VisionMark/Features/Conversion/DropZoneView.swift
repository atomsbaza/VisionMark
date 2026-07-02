import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DropZoneView: View {
    let onDropFiles: ([URL]) -> Void
    var isCompact: Bool = false

    @State private var isTargeted = false

    var body: some View {
        Group {
            if isCompact {
                compactContent
            } else {
                largeContent
            }
        }
        .background(background)
        .onDrop(of: [.pdf, .folder, .fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        .animation(.smooth, value: isTargeted)
    }

    private var largeContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .symbolEffect(.bounce, value: isTargeted)
            Text("Drop PDF files or folders here")
                .font(.headline)
            Text("or choose files to convert to Markdown")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Choose Files…", action: presentOpenPanel)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var compactContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Text("Drop more PDFs")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Choose Files…", action: presentOpenPanel)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(isTargeted ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(Color.secondary.opacity(0.08)))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: [6])
                    )
            )
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    onDropFiles([url])
                }
            }
        }
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .folder]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            onDropFiles(panel.urls)
        }
    }
}
