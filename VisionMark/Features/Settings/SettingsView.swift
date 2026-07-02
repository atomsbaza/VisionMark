import SwiftUI
import AppKit

struct SettingsView: View {
    let settings: AppSettings

    var body: some View {
        Form {
            Picker("OCR mode", selection: Binding(
                get: { settings.ocrMode },
                set: { settings.ocrMode = $0 }
            )) {
                ForEach(OCRMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            Toggle("Save Markdown next to source PDF", isOn: Binding(
                get: { settings.useSourceFolderForOutput },
                set: { settings.useSourceFolderForOutput = $0 }
            ))

            Toggle("Embed page images (lets AI read diagrams & pictures)", isOn: Binding(
                get: { settings.embedPageImages },
                set: { settings.embedPageImages = $0 }
            ))

            if !settings.useSourceFolderForOutput {
                HStack {
                    Text(settings.resolvedOutputDirectory()?.path ?? "No folder chosen")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Choose…", action: chooseOutputDirectory)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.setOutputDirectory(url)
        }
    }
}
