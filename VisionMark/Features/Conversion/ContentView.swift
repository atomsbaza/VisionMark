import SwiftUI

struct ContentView: View {
    let viewModel: ConversionViewModel
    let settings: AppSettings

    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 16) {
            DropZoneView(onDropFiles: viewModel.addFiles, isCompact: !viewModel.jobs.isEmpty)

            if !viewModel.jobs.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text("Files")
                        .font(.title3.weight(.semibold))
                    Text("\(viewModel.jobs.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    Spacer()
                }

                FileListView(jobs: viewModel.jobs)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 420)
        .animation(.smooth, value: viewModel.jobs.count)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.convertAll()
                } label: {
                    Label(viewModel.isConverting ? "Converting…" : "Convert All", systemImage: "sparkles")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isConverting || viewModel.jobs.isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { viewModel.cancelAll() }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.isConverting)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: settings)
        }
    }
}
