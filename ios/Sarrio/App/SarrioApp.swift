import SwiftUI

@main
struct SarrioApp: App {
    @State private var session = SessionStore()
    private let api: APIClient
    private let peakPackStore: PeakPackStore

    init() {
        let api = APIClient(baseURL: AppConfig.apiBaseURL)
        self.api = api
        self.peakPackStore = PeakPackStore(api: api)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(\.apiClient, api)
                .environment(\.peakPackStore, peakPackStore)
                .tint(.accentColor)
        }
    }
}
