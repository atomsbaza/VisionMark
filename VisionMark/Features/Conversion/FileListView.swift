import SwiftUI

struct FileListView: View {
    let jobs: [ConversionJob]

    var body: some View {
        if jobs.isEmpty {
            ContentUnavailableView("No files yet", systemImage: "tray", description: Text("Drop PDFs above to get started."))
        } else {
            List(jobs) { job in
                FileRowView(job: job)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}
