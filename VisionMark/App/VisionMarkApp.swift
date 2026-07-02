import SwiftUI

@main
struct VisionMarkApp: App {
    @State private var settings = AppSettings()
    @State private var viewModel: ConversionViewModel

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _viewModel = State(initialValue: ConversionViewModel(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, settings: settings)
        }
        .windowResizability(.contentSize)
    }
}
