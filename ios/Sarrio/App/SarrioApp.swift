import SwiftUI

@main
struct SarrioApp: App {
    @State private var session: SessionStore
    private let api: APIClient
    private let peakPackStore: PeakPackStore

    init() {
        let api = APIClient(baseURL: AppConfig.apiBaseURL)
        self.api = api
        self.peakPackStore = PeakPackStore(api: api)
        _session = State(initialValue: SessionStore(api: api))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(\.apiClient, api)
                .environment(\.peakPackStore, peakPackStore)
                .tint(Theme.Colors.accent)
                // Estética clara por decisión de diseño.
                .preferredColorScheme(.light)
                .task { await session.restore() }
        }
    }
}
