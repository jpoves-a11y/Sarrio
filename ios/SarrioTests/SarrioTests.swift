import Testing
@testable import Sarrio

/// Tests de la app (los de lógica pura viven en Packages/SarrioKit y se ejecutan con `swift test`).
@Suite struct AppConfigTests {
    @Test func apiBaseURLHasScheme() {
        #expect(AppConfig.apiBaseURL.scheme?.hasPrefix("http") == true)
    }
}
